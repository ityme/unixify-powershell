$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot '..\profile.ps1')
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
$gitExe = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$gitModule = (Get-Command Get-GitCompletion).Module
$trace = Join-Path $HOME 'git-query-trace.jsonl'
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}
function Test-Cache {
    param([string]$Name, [scriptblock]$Body)
    try {
        if (Get-Command Clear-GitCompletionCache -ErrorAction SilentlyContinue) { Clear-GitCompletionCache }
        [IO.File]::WriteAllText($trace, '')
        & $Body
        $script:Passed++
    } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Query {
    param([string]$Line)
    @((Complete-HookLine -Line $Line).Matches | ForEach-Object CompletionText)
}
function Query-Count {
    $count = 0
    foreach ($line in [IO.File]::ReadAllLines($trace)) {
        $record = $line | ConvertFrom-Json
        if ($record.event -eq 'start' -and ('for-each-ref' -in $record.argv -or 'remote' -in $record.argv)) { $count++ }
    }
    $count
}
function Fixture-Git {
    & $gitExe @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fixture Git failed' }
}

$first = Join-Path $HOME "first repo's"
$second = Join-Path $HOME 'second repo'
foreach ($root in @($first, $second)) {
    [void][IO.Directory]::CreateDirectory($root)
    Fixture-Git init --initial-branch=main $root
    Fixture-Git -C $root -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --allow-empty -m fixture
}
Fixture-Git -C $first branch feature/first
Fixture-Git -C $second branch feature/second
Fixture-Git -C $first remote add origin https://example.invalid/first.git
Fixture-Git -C $first update-ref refs/remotes/origin/main HEAD
$oldTrace = $env:GIT_TRACE2_EVENT
$env:GIT_TRACE2_EVENT = $trace
Push-Location $first
try {
    Test-Cache 'different prefixes reuse the same successful Git query' {
        Assert-Equal ((Query 'git switch f') -join '|') 'feature/first'
        Assert-Equal ((Query 'git switch fe') -join '|') 'feature/first'
        Assert-Equal (Query-Count) 1
    }
    Test-Cache 'different query types do not share results' {
        Assert-Equal ((Query 'git pull o') -join '|') 'origin'
        Assert-Equal ((Query 'git pull origin m') -join '|') 'main'
        Assert-Equal ((Query 'git pull or') -join '|') 'origin'
        Assert-Equal (Query-Count) 2
    }
    Test-Cache 'working directories isolate repository results' {
        Assert-Equal ((Query 'git switch f') -join '|') 'feature/first'
        Push-Location $second
        try { Assert-Equal ((Query 'git switch f') -join '|') 'feature/second' } finally { Pop-Location }
        Assert-Equal (Query-Count) 2
    }
    Test-Cache 'git -C arguments isolate repository results' {
        Assert-Equal ((Query 'git switch f') -join '|') 'feature/first'
        Assert-Equal ((Query ('git -C ' + (ConvertTo-TestLiteral $second) + ' switch f')) -join '|') 'feature/second'
        Assert-Equal (Query-Count) 2
    }
    Test-Cache 'external ref changes expire after one second' {
        $null = Query 'git switch external'
        Fixture-Git branch external-created
        Assert-Equal (Query 'git switch external').Count 0
        Assert-Equal (Query-Count) 1
        Start-Sleep -Milliseconds 1100
        Assert-Equal ((Query 'git switch external') -join '|') 'external-created'
        Assert-Equal (Query-Count) 2
    }
    Test-Cache 'a real command invalidates query data while whitespace keeps it' {
        $null = Query 'git switch command'
        Set-HookPromptInput -Line " `t "
        $null = Query 'git switch command'
        Assert-Equal (Query-Count) 1
        Set-HookPromptInput -Line 'git branch command-created'
        Fixture-Git branch command-created
        Assert-Equal ((Query 'git switch command') -join '|') 'command-created'
        Assert-Equal (Query-Count) 2
    }
    Test-Cache 'repository-selecting Git environment changes invalidate results' {
        $saved = $env:GIT_DIR
        try {
            $null = Query 'git switch f'
            $env:GIT_DIR = Join-Path $second '.git'
            Assert-Equal ((Query 'git switch f') -join '|') 'feature/second'
            Assert-Equal (Query-Count) 2
        } finally { $env:GIT_DIR = $saved }
    }
    Test-Cache 'failed Git queries are retried rather than cached' {
        Push-Location $HOME
        try {
            Assert-Equal (Query 'git switch ').Count 0
            Assert-Equal (Query 'git switch ').Count 0
            Assert-Equal (Query-Count) 2
        } finally { Pop-Location }
    }
    Test-Cache 'empty successful queries are cached too' {
        $null = Query 'git checkout v-no-tag'
        $null = Query 'git checkout v-no-tag'
        Assert-Equal (Query-Count) 1
        # Query a namespace with no refs directly, before candidate filtering.
        & $gitModule { Read-GitCompletionData @() @('for-each-ref', '--format=%(refname)', 'refs/tags') } | Out-Null
        & $gitModule { Read-GitCompletionData @() @('for-each-ref', '--format=%(refname)', 'refs/tags') } | Out-Null
        Assert-Equal (Query-Count) 2
    }
    Test-Cache 'query cache is bounded and old entries are evicted' {
        $savedLifetime = & $gitModule { $script:GitCacheLifetimeMs }
        try {
            # Isolate eviction from TTL expiry while filling more than 16 query keys.
            & $gitModule { $script:GitCacheLifetimeMs = 60000 }
            for ($i = 0; $i -lt 20; $i++) {
                & $gitModule { param($i) Read-GitCompletionData @() @('for-each-ref', '--format=%(refname)', "refs/heads/cache-$i") } $i | Out-Null
            }
            Assert-Equal (& $gitModule { $script:GitQueryCache.Count }) 16
            & $gitModule { Read-GitCompletionData @() @('for-each-ref', '--format=%(refname)', 'refs/heads/cache-19') } | Out-Null
            Assert-Equal (Query-Count) 20
            & $gitModule { Read-GitCompletionData @() @('for-each-ref', '--format=%(refname)', 'refs/heads/cache-0') } | Out-Null
            Assert-Equal (Query-Count) 21
        } finally { & $gitModule { param($lifetime) $script:GitCacheLifetimeMs = $lifetime } $savedLifetime }
    }
    Test-Cache 'executable lookup is reused and invalidates on Path PATHEXT cwd or missing executable' {
        $savedPath = $env:PATH
        $savedExtensions = $env:PATHEXT
        try {
            & $gitModule {
                $script:GitExecutable = $null
                $script:ExecutableLookups = 0
                Set-Item Function:script:Get-Command {
                    param($Name, $CommandType, $ErrorAction)
                    $script:ExecutableLookups++
                    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
                }
            }
            $resolved = & $gitModule { param($cwd) Resolve-GitCompletionExecutable $cwd } $first
            Assert-Equal $resolved $gitExe
            $null = & $gitModule { param($cwd) Resolve-GitCompletionExecutable $cwd } $first
            Assert-Equal (& $gitModule { $script:ExecutableLookups }) 1
            $env:PATH += ';' + (Join-Path $HOME 'another-search-directory')
            $null = & $gitModule { param($cwd) Resolve-GitCompletionExecutable $cwd } $first
            Assert-Equal (& $gitModule { $script:ExecutableLookups }) 2
            $env:PATHEXT += ';.UPWSHTEST'
            $null = & $gitModule { param($cwd) Resolve-GitCompletionExecutable $cwd } $first
            Assert-Equal (& $gitModule { $script:ExecutableLookups }) 3
            Push-Location $second
            try { $null = & $gitModule { param($cwd) Resolve-GitCompletionExecutable $cwd } $second }
            finally { Pop-Location }
            Assert-Equal (& $gitModule { $script:ExecutableLookups }) 4
            & $gitModule { $script:GitExecutable.Path = [IO.Path]::Combine($HOME, 'not-an-executable.exe') }
            $null = & $gitModule { param($cwd) Resolve-GitCompletionExecutable $cwd } $second
            Assert-Equal (& $gitModule { $script:ExecutableLookups }) 5
        } finally {
            $env:PATH = $savedPath
            $env:PATHEXT = $savedExtensions
            & $gitModule {
                Remove-Item Function:Get-Command
                Remove-Variable ExecutableLookups -Scope Script
                $script:GitExecutable = $null
                Clear-GitCompletionCache
            }
        }
    }
    Test-Cache 'a missing Git executable is not permanently cached' {
        $savedPath = $env:PATH
        try {
            $env:PATH = Join-Path $HOME 'empty-search-directory'
            $null = Query 'git switch f'
            Assert-Equal (Query-Count) 0
            $env:PATH = $savedPath
            Assert-Equal ((Query 'git switch f') -join '|') 'feature/first'
            Assert-Equal (Query-Count) 1
        } finally { $env:PATH = $savedPath }
    }
    Test-Cache 'cache hits and misses preserve native exit status' {
        $global:LASTEXITCODE = 7
        $null = Query 'git switch f'
        Assert-Equal $global:LASTEXITCODE 7
        $null = Query 'git switch fe'
        Assert-Equal $global:LASTEXITCODE 7
    }
} finally {
    Pop-Location
    $env:GIT_TRACE2_EVENT = $oldTrace
}
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) Git cache tests failed."
}
Write-Output "$script:Passed Git cache tests passed."
