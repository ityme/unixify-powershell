param(
    [ValidateRange(1, 10000)][int]$Samples = 60,
    [ValidateRange(0.01, 10000)][double]$BudgetMs = 30,
    [switch]$Enforce,
    [switch]$Worker,
    [string]$RuntimeProfile = (Join-Path $PSScriptRoot '..\src\profile.ps1')
)

$ErrorActionPreference = 'Stop'
if (-not $Worker) {
    . (Join-Path $PSScriptRoot '_test_host.ps1')
    $benchHome = Join-Path ([IO.Path]::GetTempPath()) ('upwsh-bench-' + [Guid]::NewGuid().ToString('N'))
    $benchEnvironment = @{}
    if (-not $env:STARSHIP_CONFIG) {
        $config = Join-Path $HOME '.config\starship.toml'
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            $benchEnvironment.STARSHIP_CONFIG = $config
        }
    }
    $arguments = @('-Worker', '-Samples', "$Samples", '-BudgetMs', "$BudgetMs", '-RuntimeProfile', ([IO.Path]::GetFullPath($RuntimeProfile)))
    if ($Enforce) { $arguments += '-Enforce' }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-UpwshTestProcess -UserHome $benchHome -File $PSCommandPath -Arguments $arguments -WorkingDirectory (Get-Location).ProviderPath -Environment $benchEnvironment
        Write-Output $result.Text
        Write-Output ('Process + benchmark: {0:N1} ms' -f $watch.Elapsed.TotalMilliseconds)
        exit $result.Code
    } finally {
        Remove-Item -LiteralPath $benchHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$watch = [Diagnostics.Stopwatch]::StartNew()
. $RuntimeProfile
$startupMs = $watch.Elapsed.TotalMilliseconds
$consoleWriter = [Console]::Out
try {
    [Console]::SetOut([IO.TextWriter]::Null)
    $watch.Restart()
    $null = prompt
    $firstPromptMs = $watch.Elapsed.TotalMilliseconds
    $inputHook = Get-Command Set-HookPromptInput -ErrorAction SilentlyContinue
    for ($index = 0; $index -lt 5; $index++) {
        if ($inputHook) { & $inputHook -Line '' }
        $null = prompt
    }
    $durations = for ($index = 0; $index -lt $Samples; $index++) {
        $watch.Restart()
        # The Enter handler records input before checking completeness and rendering prompt.
        if ($inputHook) { & $inputHook -Line '' }
        $null = Test-CompleteCommandLine -InputScript ''
        $null = prompt
        $watch.Elapsed.TotalMilliseconds
    }
} finally {
    [Console]::SetOut($consoleWriter)
}
$sorted = @($durations | Sort-Object)
$p95 = $sorted[[Math]::Ceiling($Samples * 0.95) - 1]
[pscustomobject]@{
    RuntimeProfile = [IO.Path]::GetFullPath($RuntimeProfile)
    Samples = $Samples
    StartupMs = [Math]::Round($startupMs, 2)
    FirstPromptMs = [Math]::Round($firstPromptMs, 2)
    EmptyEnterMedianMs = [Math]::Round($sorted[[int]($Samples / 2)], 2)
    EmptyEnterP95Ms = [Math]::Round($p95, 2)
    EmptyEnterMaxMs = [Math]::Round($sorted[-1], 2)
    BudgetMs = $BudgetMs
    Passed = $p95 -lt $BudgetMs
} | ConvertTo-Json -Compress
if ($Enforce -and $p95 -ge $BudgetMs) { exit 1 }
