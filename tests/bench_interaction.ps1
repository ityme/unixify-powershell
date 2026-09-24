param(
    [ValidateRange(1, 10000)][int]$Files = 1000,
    [ValidateRange(1, 1000)][int]$Samples = 10,
    [string]$RuntimeRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))),
    [switch]$Worker
)
$ErrorActionPreference = 'Stop'
if (-not $Worker) {
    . (Join-Path $PSScriptRoot '_test_host.ps1')
    $testHome = Join-Path ([IO.Path]::GetTempPath()) ('upwsh-interaction-' + [guid]::NewGuid().ToString('N'))
    try {
        $result = Invoke-UpwshTestProcess -UserHome $testHome -File $PSCommandPath -Arguments @('-Worker', '-Files', "$Files", '-Samples', "$Samples", '-RuntimeRoot', $RuntimeRoot)
        Write-Output $result.Text
        exit $result.Code
    } finally {
        Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

. (Join-Path $RuntimeRoot 'profile.ps1')
$fixture = Join-Path $HOME 'fixture'
[void][IO.Directory]::CreateDirectory($fixture)
for ($i = 0; $i -lt $Files; $i++) {
    [IO.File]::WriteAllText((Join-Path $fixture ('entry-{0:d5}.txt' -f $i)), '')
}
Push-Location $HOME
$writer = [Console]::Out
$records = [Collections.Generic.List[object]]::new()
try {
    [Console]::SetOut([IO.TextWriter]::Null)
    $work = [ordered]@{
        TermPrompt = { Sync-TermPrompt -Succeeded $true -ExitCode 0 }
        TermCommand = { Sync-TermCommand -Command 'example /c/work' }
        Filesystem = { $null = @(Get-UnixPathCompletion -WordToComplete './fixture/entry-') }
        Completion = {
            $line = 'example ./fixture/entry-'
            $state = Complete-HookLine -Line $line
            $current = $line.Substring($state.ReplacementIndex, $state.ReplacementLength)
            $params = @{ Matches = $state.Matches; CurrentText = $current; LiteralPaths = [bool]$state.LiteralPaths }
            if ($state.PSObject.Properties['MatchesNormalized']) { $params.Normalized = $state.MatchesNormalized }
            $decision = Get-CompletionDecision @params
            if ($decision.MatchCount -ne $Files) { throw "expected $Files completion candidates, got $($decision.MatchCount)" }
        }
    }
    foreach ($name in $work.Keys) {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        & $work[$name]
        $cold = $timer.Elapsed.TotalMilliseconds
        for ($i = 0; $i -lt 3; $i++) { & $work[$name] }
        $count = if ($name -like 'Term*') { 100 } else { $Samples }
        $times = for ($i = 0; $i -lt $count; $i++) {
            $timer.Restart()
            & $work[$name]
            $timer.Elapsed.TotalMilliseconds
        }
        $sorted = @($times | Sort-Object)
        $records.Add([pscustomobject]@{
            Stage = $name
            Samples = $count
            ColdMs = [math]::Round($cold, 2)
            MedianMs = [math]::Round($sorted[[int]($count / 2)], 2)
            P95Ms = [math]::Round($sorted[[math]::Ceiling($count * 0.95) - 1], 2)
        })
    }
} finally {
    [Console]::SetOut($writer)
    Pop-Location
}
[pscustomobject]@{ Files = $Files; Stages = $records } | ConvertTo-Json -Depth 4 -Compress
