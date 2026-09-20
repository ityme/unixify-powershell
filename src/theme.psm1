# Local theme data and selection. JSON is parsed, never evaluated as PowerShell.
$script:ThemeRoot = [IO.Path]::Combine($PSScriptRoot, 'themes')
$script:ThemeSelection = [IO.Path]::Combine($PSScriptRoot, 'custom', 'theme.json')
$script:ThemeCache = $null
$script:ThemeStamp = $null
$script:ThemeRevision = 0
$script:ThemeWarningStamp = $null

function Assert-UpwshThemeName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 80 -or
        $Name -notmatch '^[\p{L}\p{N}][\p{L}\p{N} _-]*$' -or $Name.TrimEnd() -cne $Name) {
        throw 'theme name must contain letters, numbers, spaces, _ or - (no paths)'
    }
}

function Read-UpwshTheme {
    param([string]$Name)
    Assert-UpwshThemeName $Name
    $file = [IO.Path]::Combine($script:ThemeRoot, "$Name.json")
    if (-not [IO.File]::Exists($file)) { throw "unknown local theme: $Name" }
    if ([IO.FileInfo]::new($file).Length -gt 65536) { throw "theme is too large: $Name" }
    $data = [IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($data -isnot [Collections.IDictionary] -or
        ($data.Version -isnot [int] -and $data.Version -isnot [long]) -or
        $data.Version -ne 1 -or $data.Name -isnot [string]) {
        throw "invalid theme header: $Name"
    }
    Assert-UpwshThemeName $data.Name
    if ($data.Name -ine $Name) { throw "theme name does not match its file: $Name" }
    foreach ($section in @('Colors', 'Symbols', 'Display')) {
        if ($data[$section] -isnot [Collections.IDictionary]) { throw "missing $section in theme $Name" }
    }
    foreach ($key in @('UserHost', 'Directory', 'Branch', 'Duration', 'Success', 'Error')) {
        if ($data.Colors[$key] -isnot [string] -or $data.Colors[$key] -notmatch '^#[0-9a-fA-F]{6}$') {
            throw "invalid color $key in theme $Name; use #RRGGBB"
        }
    }
    foreach ($key in @('Success', 'Error')) {
        $symbol = $data.Symbols[$key]
        if ($symbol -isnot [string] -or $symbol.Length -lt 1 -or $symbol.Length -gt 16 -or $symbol -match '[\s\x00-\x1f\x7f-\x9f]') {
            throw "invalid symbol $key in theme $Name"
        }
    }
    foreach ($key in @('ShowUserHost', 'ShowGitBranch', 'ShowDuration', 'ShowExitCode', 'DirectoryItalic', 'SymbolBold', 'ErrorBold')) {
        if ($data.Display[$key] -isnot [bool]) { throw "invalid boolean $key in theme $Name" }
    }
    if ($data.Display.DirectoryStyle -isnot [string] -or $data.Display.DirectoryStyle -cnotin @('folder', 'path')) {
        throw "invalid DirectoryStyle in theme $Name"
    }
    $threshold = $data.Display.DurationMinMs
    if (($threshold -isnot [int] -and $threshold -isnot [long]) -or $threshold -lt 0 -or $threshold -gt 86400000) {
        throw "invalid DurationMinMs in theme $Name"
    }
    return $data
}

function Get-UpwshThemeStamp {
    $info = [IO.FileInfo]::new($script:ThemeSelection)
    if (-not $info.Exists) { return 'default' }
    return "$($info.LastWriteTimeUtc.Ticks):$($info.Length)"
}

function Get-UpwshTheme {
    [CmdletBinding()]
    param([switch]$Reload)
    $stamp = Get-UpwshThemeStamp
    if (-not $Reload -and $script:ThemeCache -and $script:ThemeStamp -ceq $stamp) { return $script:ThemeCache }
    try {
        $name = 'iWonder'
        if ([IO.File]::Exists($script:ThemeSelection)) {
            if ([IO.FileInfo]::new($script:ThemeSelection).Length -gt 4096) { throw 'theme selection file is too large' }
            $selection = [IO.File]::ReadAllText($script:ThemeSelection) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($selection -isnot [Collections.IDictionary] -or $selection.Theme -isnot [string] -or
                -not $selection.Theme.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'theme selection must reference a local .json file'
            }
            $name = $selection.Theme.Substring(0, $selection.Theme.Length - 5)
        }
        $theme = Read-UpwshTheme $name
        $script:ThemeWarningStamp = $null
    } catch {
        if ($script:ThemeWarningStamp -cne $stamp) {
            Write-Warning "upwsh theme: $($_.Exception.Message); keeping the previous theme or iWonder"
            $script:ThemeWarningStamp = $stamp
        }
        $theme = if ($script:ThemeCache) { $script:ThemeCache } else { Read-UpwshTheme 'iWonder' }
    }
    $script:ThemeCache = $theme
    $script:ThemeStamp = $stamp
    $script:ThemeRevision++
    return $theme
}

function Get-UpwshThemeRevision {
    $null = Get-UpwshTheme
    return $script:ThemeRevision
}

function Get-UpwshThemeList {
    [CmdletBinding()]
    param()
    $active = (Get-UpwshTheme).Name
    if (-not [IO.Directory]::Exists($script:ThemeRoot)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $script:ThemeRoot -Filter '*.json' -File | Sort-Object Name) {
        try {
            $theme = Read-UpwshTheme $file.BaseName
            [pscustomobject]@{ Name = $theme.Name; Active = $theme.Name -ieq $active }
        } catch { Write-Warning "upwsh theme: skipping $($file.Name): $($_.Exception.Message)" }
    }
}

function Set-UpwshTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    # Fully validate before changing the reference; a bad theme cannot break the current prompt.
    $theme = Read-UpwshTheme $Name
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:ThemeSelection))
    $temp = $script:ThemeSelection + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $text = @{ Theme = $theme.Name + '.json' } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($temp, $text + [Environment]::NewLine)
        [IO.File]::Move($temp, $script:ThemeSelection, $true)
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
    $script:ThemeCache = $theme
    $script:ThemeStamp = Get-UpwshThemeStamp
    $script:ThemeRevision++
    $script:ThemeWarningStamp = $null
    return $theme.Name
}

Export-ModuleMember -Function Get-UpwshTheme, Get-UpwshThemeRevision, Get-UpwshThemeList, Set-UpwshTheme
