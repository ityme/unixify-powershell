param(
    [ValidateRange(1, 1000)][int]$Samples = 20,
    [string]$RuntimeRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [switch]$Worker
)

$ErrorActionPreference = 'Stop'
if (-not $Worker) {
    . (Join-Path $PSScriptRoot '_test_host.ps1')
    $testHome = Join-Path ([IO.Path]::GetTempPath()) ('upwsh-git-bench-' + [guid]::NewGuid().ToString('N'))
    try {
        $result = Invoke-UpwshTestProcess -UserHome $testHome -File $PSCommandPath -Arguments @(
            '-Worker', '-Samples', "$Samples", '-RuntimeRoot', $RuntimeRoot
        ) -WorkingDirectory (Get-Location).ProviderPath
        Write-Output $result.Text
        exit $result.Code
    } finally {
        Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

. (Join-Path $RuntimeRoot 'profile.ps1')
$hook = (Get-Command Complete-HookLine).Module
function Measure-Tab {
    param([string]$Line)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $state = Complete-HookLine -Line $Line
    $current = $Line.Substring($state.ReplacementIndex, $state.ReplacementLength)
    $decision = Get-CompletionDecision -Matches $state.Matches -CurrentText $current -Normalized:$state.MatchesNormalized -LiteralPaths:$state.LiteralPaths
    $null = & $hook { param($state, $decision) Get-HookCompletionEdit -State $state -Decision $decision } $state $decision
    [pscustomobject]@{ Ms = $watch.Elapsed.TotalMilliseconds; Candidates = $state.Matches.Count }
}

$rows = foreach ($line in @('git pul', 'git switch ', 'git pull ', 'git pull origin ')) {
    $null = Measure-Tab $line
    $misses = [Collections.Generic.List[double]]::new()
    $hits = [Collections.Generic.List[double]]::new()
    for ($index = 0; $index -lt $Samples; $index++) {
        # A command invalidates query data but keeps executable discovery warm.
        Set-HookPromptInput -Line 'benchmark'
        $fresh = Measure-Tab $line
        $repeat = Measure-Tab $line
        $misses.Add($fresh.Ms)
        $hits.Add($repeat.Ms)
    }
    $coldSorted = @($misses | Sort-Object)
    $warmSorted = @($hits | Sort-Object)
    [pscustomobject]@{
        Line = $line
        Samples = $Samples
        Candidates = $repeat.Candidates
        FreshQueryMedianMs = [math]::Round($coldSorted[[int]($Samples / 2)], 2)
        FreshQueryP95Ms = [math]::Round($coldSorted[[math]::Ceiling($Samples * 0.95) - 1], 2)
        RepeatedQueryMedianMs = [math]::Round($warmSorted[[int]($Samples / 2)], 2)
        RepeatedQueryP95Ms = [math]::Round($warmSorted[[math]::Ceiling($Samples * 0.95) - 1], 2)
    }
}
$rows | ConvertTo-Json -Compress
