$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}

$runtime = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
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
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Join-Path $HOME 'prompt-repo'
[void][IO.Directory]::CreateDirectory($root)
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
& $git init --initial-branch=dev $root 2>&1 | Out-Null
& $git -C $root -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --allow-empty -m fixture 2>&1 | Out-Null
$worktree = Join-Path $HOME 'prompt-worktree'
& $git -C $root worktree add -b feature/test $worktree 2>&1 | Out-Null
$old = Get-Location
try {
    Test-PromptRenderer 'prompt uses username, host, Unix path and branch' {
        Push-Location $root
        try {
            $text = Get-UpwshPromptText -Succeeded $true
            Assert-Contains $text ([Environment]::UserName + '@' + [Environment]::MachineName)
            Assert-Contains $text 'prompt-repo'
            Assert-Contains $text 'dev'
            Assert-True ($text -match '>\s*$') 'success prompt missing >'
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'prompt omits branch outside a repository' {
        Push-Location $HOME
        try {
            $text = Get-UpwshPromptText -Succeeded $true
            Assert-True ($text -notmatch ' dev>') 'branch leaked outside repository'
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'prompt reads branch changes from HEAD without starting Git' {
        Push-Location $root
        try {
            [IO.File]::WriteAllText((Join-Path $root '.git\HEAD'), "ref: refs/heads/feature/test`n")
            $text = Get-UpwshPromptText -Succeeded $true
            Assert-Contains $text 'feature/test'
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'prompt falls back to Git inside a worktree subdirectory' {
        $subdir = Join-Path $worktree 'src\nested'
        [void][IO.Directory]::CreateDirectory($subdir)
        Push-Location $subdir
        try {
            $text = Get-UpwshPromptText -Succeeded $false -ExitCode 1
            Assert-Contains $text 'feature/test'
            Assert-True ($text -match '!\s*$') 'failure prompt missing !'
        } finally { Pop-Location }
    }
    Test-PromptRenderer 'detached HEAD gets a readable label' {
        Push-Location $root
        try {
            [IO.File]::WriteAllText((Join-Path $root '.git\HEAD'), ('a' * 40) + "`n")
            $text = Get-UpwshPromptText -Succeeded $true
            Assert-Contains $text 'detached@aaaaaaa'
        } finally { Pop-Location }
    }
} finally { Set-Location $old; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $worktree -Recurse -Force -ErrorAction SilentlyContinue }
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) prompt renderer tests failed."
}
Write-Output "$script:Passed prompt renderer tests passed."
