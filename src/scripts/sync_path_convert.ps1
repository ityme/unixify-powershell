# Keep the standalone irm | iex entry points in sync with the shared interfaces.
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$source = [IO.Path]::Combine($PSScriptRoot, '..', 'path_convert.ps1')
$core = [IO.File]::ReadAllText($source).Replace("`r`n", "`n").TrimEnd("`n")
$begin = '# BEGIN GENERATED PATH CONVERTERS (src/path_convert.ps1)'
$end = '# END GENERATED PATH CONVERTERS'
$expected = $begin + "`n" + $core + "`n" + $end

foreach ($name in @('install.ps1', 'uninstall.ps1')) {
    $path = [IO.Path]::Combine($PSScriptRoot, $name)
    $original = [IO.File]::ReadAllText($path)
    $text = $original.Replace("`r`n", "`n")
    $start = $text.IndexOf($begin, [StringComparison]::Ordinal)
    $finish = $text.IndexOf($end, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $finish -lt $start) {
        throw "missing generated path converter markers in $name"
    }
    $length = $finish + $end.Length - $start
    if ($text.Substring($start, $length) -ceq $expected) { continue }
    if ($Check) {
        throw "$name has stale path converters; run src/scripts/sync_path_convert.ps1"
    }
    $updated = $text.Remove($start, $length).Insert($start, $expected)
    if ($original.Contains("`r`n")) { $updated = $updated.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText($path, $updated)
    Write-Output "updated $name"
}
if ($Check) { Write-Output 'Standalone path converters match src/path_convert.ps1.' }
