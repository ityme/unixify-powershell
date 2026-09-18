param(
    [ValidateRange(10, 10000)][int]$Samples = 100,
    [string]$RuntimeRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [switch]$Worker
)
$ErrorActionPreference = 'Stop'
if (-not $Worker) {
    . (Join-Path $PSScriptRoot '_test_host.ps1')
    $testHome = Join-Path ([IO.Path]::GetTempPath()) ('upwsh-term-bench-' + [guid]::NewGuid().ToString('N'))
    try {
        $result = Invoke-UpwshTestProcess -UserHome $testHome -File $PSCommandPath -Arguments @(
            '-Worker', '-Samples', "$Samples", '-RuntimeRoot', $RuntimeRoot
        ) -WorkingDirectory (Get-Location).ProviderPath
        Write-Output $result.Text
        exit $result.Code
    } finally { Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue }
}
Import-Module (Join-Path $RuntimeRoot 'term.psm1') -DisableNameChecking
$original = [Console]::Out
$rows = [Collections.Generic.List[object]]::new()
try {
    foreach ($name in @('idle', 'begin', 'finish')) {
        $action = switch ($name) {
            'idle' { { Sync-TermPrompt -CommandCompleted:$false } }
            'begin' { { Sync-TermCommand -Command 'example --fixture' } }
            'finish' { { Sync-TermPrompt -CommandCompleted:$true -Succeeded $true -ExitCode 0 } }
        }
        [Console]::SetOut([IO.TextWriter]::Null)
        for ($i = 0; $i -lt 10; $i++) {
            if ($name -eq 'finish') { Sync-TermCommand 'example --fixture' }
            & $action
        }
        $watch = [Diagnostics.Stopwatch]::new()
        $times = for ($i = 0; $i -lt $Samples; $i++) {
            if ($name -eq 'finish') { Sync-TermCommand 'example --fixture' }
            $watch.Restart()
            & $action
            $watch.Elapsed.TotalMilliseconds
        }
        if ($name -eq 'finish') { Sync-TermCommand 'example --fixture' }
        if ($name -eq 'begin') { Sync-TermPrompt -CommandCompleted:$true }
        $writer = [IO.StringWriter]::new()
        try {
            [Console]::SetOut($writer)
            & $action
            $text = $writer.ToString()
        } finally { [Console]::SetOut([IO.TextWriter]::Null); $writer.Dispose() }
        $sorted = @($times | Sort-Object)
        $rows.Add([pscustomobject]@{
            Stage = $name; Samples = $Samples
            MedianMs = [math]::Round($sorted[[int]($Samples / 2)], 3)
            P95Ms = [math]::Round($sorted[[math]::Ceiling($Samples * .95) - 1], 3)
            Bytes = [Text.Encoding]::UTF8.GetByteCount($text)
            OscCount = [regex]::Matches($text, '\x1b\]').Count
        })
    }
} finally { [Console]::SetOut($original) }
$rows | ConvertTo-Json -Compress
