$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}
$runtime = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
. (Join-Path $runtime 'profile.ps1')
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
function Test-PromptRenderer {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++ } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}
function Assert-Contains {
    param([string]$Text, [string]$Expected)
    if (-not $Text.Contains($Expected)) { throw "expected <$Expected> in <$Text>" }
}
function Fixture-Git {
    & $script:Git @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fixture Git failed: $args" }
}
function Plain { param([string]$Text) $Text -replace '\x1b\[[0-9;]*m', '' }

$script:Git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$root = Join-Path $HOME 'prompt-repo'
$subdir = Join-Path $root 'src\nested'
$worktree = Join-Path $HOME "worktree space's"
[void][IO.Directory]::CreateDirectory($subdir)
Fixture-Git init --initial-branch=dev $root
Fixture-Git -C $root -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --allow-empty -m fixture
Fixture-Git -C $root worktree add -b feature/worktree $worktree
$identity = "$env:USERNAME@$([Environment]::MachineName.ToLowerInvariant().Split('.')[0])"
try {
    Test-PromptRenderer 'only current folder is shown, with home and drive roots special-cased' {
        Assert-Equal (Get-PromptPathText $HOME) '~'
        Assert-Equal (Get-PromptPathText $subdir) 'nested'
        Assert-Equal (Get-PromptPathText 'C:\') '/c'
        Assert-Equal (Get-PromptPathText 'C:\parent\my work\') 'my work'
        Assert-Equal (Get-PromptPathText '\\server\share\leaf') 'leaf'
    }
    Test-PromptRenderer 'root prompt matches the reference symbol and spacing' {
        Push-Location $root
        try { Assert-Equal (Get-UpwshPromptText -Color Never) "$identity prompt-repo dev ❯ " }
        finally { Pop-Location }
    }
    Test-PromptRenderer 'repository subdirectory shows branch but no parent path' {
        Push-Location $subdir
        try { Assert-Equal (Get-UpwshPromptText -Color Never) "$identity nested dev ❯ " }
        finally { Pop-Location }
    }
    Test-PromptRenderer 'a branch change in the same subdirectory is read on the next render' {
        Assert-Equal (Get-PromptGitBranch $subdir) 'dev'
        Fixture-Git -C $root switch -c feature/changed
        Assert-Equal (Get-PromptGitBranch $subdir) 'feature/changed'
        Fixture-Git -C $root switch dev
        Assert-Equal (Get-PromptGitBranch $subdir) 'dev'
    }
    Test-PromptRenderer 'worktree root and nested path show their own branch' {
        $nested = Join-Path $worktree 'inside\child'
        [void][IO.Directory]::CreateDirectory($nested)
        Assert-Equal (Get-PromptGitBranch $worktree) 'feature/worktree'
        Assert-Equal (Get-PromptGitBranch $nested) 'feature/worktree'
    }
    Test-PromptRenderer 'unborn branch resolves in a repository subdirectory' {
        $unborn = Join-Path $HOME 'unborn'
        [void][IO.Directory]::CreateDirectory((Join-Path $unborn 'inside'))
        Fixture-Git init --initial-branch=new-branch $unborn
        Assert-Equal (Get-PromptGitBranch (Join-Path $unborn 'inside')) 'new-branch'
    }
    Test-PromptRenderer 'no-repository result is not cached after a repository is created' {
        $fresh = Join-Path $HOME 'new-project'
        [void][IO.Directory]::CreateDirectory($fresh)
        Assert-Equal (Get-PromptGitBranch $fresh) ''
        Fixture-Git init --initial-branch=fresh $fresh
        Assert-Equal (Get-PromptGitBranch $fresh) 'fresh'
    }
    Test-PromptRenderer 'root HEAD is read without launching Git' {
        $module = (Get-Command Get-UpwshPromptText).Module
        $saved = & $module { (Get-Command Invoke-PromptGit).ScriptBlock }
        try {
            & $module { Set-Item Function:Invoke-PromptGit { throw 'unexpected Git subprocess' } }
            Assert-Equal (Get-PromptGitBranch $root) 'dev'
        } finally { & $module { param($body) Set-Item Function:Invoke-PromptGit $body } $saved }
    }
    Test-PromptRenderer 'detached HEAD is read both at root and in subdirectories' {
        Fixture-Git -C $root checkout --detach
        $sha = (& $script:Git -C $root rev-parse HEAD).Substring(0, 7)
        Assert-Equal (Get-PromptGitBranch $root) "detached@$sha"
        Assert-Equal (Get-PromptGitBranch $subdir) "detached@$sha"
        Fixture-Git -C $root switch dev
    }
    Test-PromptRenderer 'leaving a repository clears the branch and shows home as tilde' {
        Push-Location $HOME
        try { Assert-Equal (Get-UpwshPromptText -Color Never) "$identity ~ ❯ " }
        finally { Pop-Location }
    }
    Test-PromptRenderer 'error uses a numeric code and the same character rather than an exclamation' {
        Push-Location $root
        try {
            Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 7 -Color Never) "$identity prompt-repo dev 7❯ "
            Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 0 -Color Never) "$identity prompt-repo dev 1❯ "
            Assert-Equal (Get-UpwshPromptText -Succeeded $true -ExitCode 7 -Color Never) "$identity prompt-repo dev ❯ "
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'duration follows the reference 2-second threshold and millisecond format' {
        Push-Location $root
        try {
            $cases = @(
                ,@(1999, '')
                ,@(2000, '2s0ms')
                ,@(2345, '2s345ms')
                ,@(60000, '1m0s0ms')
                ,@(3662123, '1h1m2s123ms')
                ,@(86400000, '1d0h0m0s0ms')
            )
            foreach ($case in $cases) {
                Assert-Equal (Get-UpwshPromptText -DurationMs $case[0] -Color Never) "$identity prompt-repo dev $($case[1])❯ "
            }
            Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 2345 -Color Never) "$identity prompt-repo dev 2s345ms7❯ "
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'truecolor palette and attributes match starship.toml reference' {
        Push-Location $root
        try {
            $esc = [char]27
            $text = Get-UpwshPromptText -Color Always
            Assert-Contains $text "$esc[0;38;2;34;197;94;49m$env:USERNAME"
            Assert-Contains $text "$esc[0;38;2;34;197;94;49m@"
            Assert-Contains $text "$esc[0;38;2;34;197;94;49m$([Environment]::MachineName.ToLowerInvariant().Split('.')[0]) "
            Assert-Contains $text "$esc[0;3;38;2;234;179;8;49mprompt-repo "
            Assert-Contains $text "$esc[0;38;2;6;182;212;49mdev "
            Assert-Contains $text "$esc[0;1;38;2;13;180;71;49m❯"
            Assert-Equal (Plain $text) "$identity prompt-repo dev ❯ "
            $text = Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 2345 -Color Always
            Assert-Contains $text "$esc[0;38;2;115;218;202;49m2s345ms"
            Assert-Contains $text "$esc[0;1;38;2;209;91;113;49m7"
            Assert-Contains $text "$esc[0;1;38;2;209;91;113;49m❯"
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'redirected output and NO_COLOR stay readable without ANSI' {
        Push-Location $root
        $saved = $env:NO_COLOR
        try {
            Assert-Equal (Get-UpwshPromptText -Color Auto) (Get-UpwshPromptText -Color Never)
            $env:NO_COLOR = '1'
            Assert-Equal (Get-UpwshPromptText -Color Auto) (Get-UpwshPromptText -Color Never)
        } finally { $env:NO_COLOR = $saved; Pop-Location }
    }
    Test-PromptRenderer 'provider locations do not show an unrelated filesystem branch' {
        Push-Location Env:\
        try { Assert-Equal (Get-UpwshPromptText -Color Never) "$identity Env:\ ❯ " }
        finally { Pop-Location }
    }
    Test-PromptRenderer 'prompt uses completed duration even when OSC is off' {
        Push-Location $root
        $hook = (Get-Command prompt).Module
        $term = (Get-Command Sync-TermPrompt).Module
        try {
            Set-TermReporting -Mode Off
            Set-HookPromptInput -Line '$null=1'
            & $term { $script:TermCommandStarted = [Diagnostics.Stopwatch]::GetTimestamp() - [long](3.0 * [Diagnostics.Stopwatch]::Frequency) }
            $text = prompt
            if ($text -notmatch 'dev 3s\d+ms❯ $') { throw "duration not propagated: $text" }
            Assert-Equal (prompt) $text
            Set-HookPromptInput -Line '$null=2'
            $text = prompt
            Assert-Equal $text "$identity prompt-repo dev ❯ "
        } finally { Set-TermReporting -Reset -Mode On; Pop-Location }
    }
} finally {
    Remove-Item -LiteralPath $root, $worktree -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) prompt renderer tests failed."
}
Write-Output "$script:Passed prompt renderer tests passed."
