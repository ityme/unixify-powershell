# Local theme data and selection. JSON is parsed, never evaluated as PowerShell.
$script:ThemeBundledRoot = [IO.Path]::Combine($PSScriptRoot, 'themes')
$script:ThemeCustomRoot = [IO.Path]::Combine($PSScriptRoot, 'custom', 'themes')
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

function Assert-ThemeKeys {
    param($Data, [string[]]$Allowed, [string]$Context)
    if ($Data -isnot [Collections.IDictionary]) { throw "expected an object: $Context" }
    foreach ($key in $Data.Keys) {
        if ($key -cnotin $Allowed) { throw "unknown setting $Context.$key" }
    }
}

function Assert-ThemeText {
    param($Value, [string]$Context, [int]$Maximum = 128)
    if ($Value -isnot [string] -or $Value.Length -gt $Maximum -or $Value -match '[\x00-\x1f\x7f-\x9f\u2028\u2029]') {
        throw "invalid single-line text: $Context"
    }
}

function Assert-ThemeColor {
    param($Value, [string]$Context, [bool]$Background, [bool]$References)
    $default = if ($Background) { 'transparent' } else { 'default' }
    if ($Value -is [string] -and ($Value -cmatch '^#[0-9a-fA-F]{6}$' -or $Value -ceq $default -or
        ($References -and $Value -cin @('previous.background', 'next.background')))) { return }
    throw "invalid color $Context; use #RRGGBB or $default"
}

function Get-UpwshThemeFile {
    param([string]$Name)
    Assert-UpwshThemeName $Name
    $custom = [IO.Path]::Combine($script:ThemeCustomRoot, "$Name.json")
    if ([IO.File]::Exists($custom)) { return $custom }
    $bundled = [IO.Path]::Combine($script:ThemeBundledRoot, "$Name.json")
    if ([IO.File]::Exists($bundled)) { return $bundled }
    throw "unknown local theme: $Name"
}

function Read-UpwshTheme {
    param([string]$Name)
    $file = Get-UpwshThemeFile $Name
    if ([IO.FileInfo]::new($file).Length -gt 65536) { throw "theme is too large: $Name" }
    $data = [IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($data -isnot [Collections.IDictionary] -or
        ($data.Version -isnot [int] -and $data.Version -isnot [long]) -or $data.Version -ne 2) {
        throw "theme $Name requires Version 2 (Order/Modules); old formats are not supported"
    }
    Assert-ThemeKeys $data @('Version', 'Name', 'AddNewline', 'Order', 'Modules', '_Comment') $Name
    if (-not $data.Contains('AddNewline')) { $data.Add('AddNewline', $false) }
    if ($data.AddNewline -isnot [bool]) { throw "invalid AddNewline in theme $Name" }
    if ($data.Name -isnot [string]) { throw "invalid theme name: $Name" }
    Assert-UpwshThemeName $data.Name
    if ($data.Name -ine $Name) { throw "theme name does not match its file: $Name" }
    if ($data.Modules -isnot [Collections.IDictionary] -or $data.Modules.Count -lt 1 -or $data.Modules.Count -gt 64) {
        throw "theme $Name requires 1-64 Modules"
    }
    if ($data.Order -isnot [array] -or $data.Order.Count -lt 1 -or $data.Order.Count -gt 128) {
        throw "theme $Name requires an Order array with 1-128 entries"
    }
    $builtins = @('user', 'host', 'directory', 'git', 'duration', 'exitCode', 'symbol')
    foreach ($id in $data.Modules.Keys) {
        if ($id -cnotmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,39}$') { throw "invalid module name: $id" }
        $module = $data.Modules[$id]
        $type = if ($id -cin $builtins) { $id } else { 'text' }
        $allowed = @('Type', 'Enabled', 'When', 'Foreground', 'Background', 'Bold', 'Italic', 'Prefix', 'Suffix', '_Comment')
        switch ($type) {
            'directory' { $allowed += 'Style' }
            'duration' { $allowed += 'MinMs' }
            'symbol' { $allowed += @('Text', 'Failure') }
            'text' { $allowed += @('Text', 'AttachTo') }
        }
        Assert-ThemeKeys $module $allowed "$Name.Modules.$id"
        if ($type -eq 'text' -and $module.Type -cne 'text') { throw "custom module $id requires Type: text" }
        if ($module.Contains('Type') -and ($module.Type -isnot [string] -or $module.Type -cne $type)) { throw "invalid Type for module $id" }
        $module.Type = $type
        $defaults = @{ Enabled = $true; When = 'always'; Foreground = 'default'; Background = 'transparent'; Bold = $false; Italic = $false; Prefix = ''; Suffix = '' }
        if ($type -eq 'exitCode') { $defaults.When = 'failure' }
        if ($type -eq 'directory') { $defaults.Style = 'folder' }
        if ($type -eq 'duration') { $defaults.MinMs = 2000 }
        if ($type -eq 'symbol') { $defaults.Text = '❯'; $defaults.Failure = @{} }
        if ($type -eq 'text') { $defaults.AttachTo = @() }
        foreach ($key in $defaults.Keys) { if (-not $module.Contains($key)) { $module[$key] = $defaults[$key] } }
        foreach ($key in @('Enabled', 'Bold', 'Italic')) {
            if ($module[$key] -isnot [bool]) { throw "invalid boolean $id.$key" }
        }
        if ($module.When -isnot [string] -or $module.When -cnotin @('always', 'success', 'failure')) { throw "invalid When for $id" }
        Assert-ThemeColor $module.Foreground "$id.Foreground" $false ($type -eq 'text')
        Assert-ThemeColor $module.Background "$id.Background" $true ($type -eq 'text')
        foreach ($key in @('Prefix', 'Suffix')) { Assert-ThemeText $module[$key] "$id.$key" }
        if ($type -eq 'directory' -and ($module.Style -isnot [string] -or $module.Style -cnotin @('folder', 'path'))) { throw "invalid directory.Style" }
        if ($type -eq 'duration' -and (($module.MinMs -isnot [int] -and $module.MinMs -isnot [long]) -or $module.MinMs -lt 0 -or $module.MinMs -gt 86400000)) { throw 'invalid duration.MinMs' }
        if ($type -in @('symbol', 'text')) { Assert-ThemeText $module.Text "$id.Text" }
        if ($type -eq 'symbol') {
            Assert-ThemeKeys $module.Failure @('Text', 'Foreground', 'Background', 'Bold', 'Italic') 'symbol.Failure'
            foreach ($key in $module.Failure.Keys) {
                $value = $module.Failure[$key]
                switch ($key) {
                    'Text' { Assert-ThemeText $value 'symbol.Failure.Text' }
                    'Foreground' { Assert-ThemeColor $value 'symbol.Failure.Foreground' $false $false }
                    'Background' { Assert-ThemeColor $value 'symbol.Failure.Background' $true $false }
                    default { if ($value -isnot [bool]) { throw "invalid boolean symbol.Failure.$key" } }
                }
            }
        }
    }
    foreach ($id in $data.Order) {
        if ($id -isnot [string] -or $id -cnotin @($data.Modules.Keys)) { throw "unknown module in Order: $id" }
    }
    foreach ($id in $data.Modules.Keys) {
        $module = $data.Modules[$id]
        if ($module.Type -ne 'text') { continue }
        if ($module.AttachTo -isnot [array] -or $module.AttachTo.Count -gt 64) { throw "AttachTo must be an array: $id" }
        foreach ($target in $module.AttachTo) {
            if ($target -isnot [string] -or $target -cnotin $builtins -or $target -cnotin $data.Order) {
                throw "AttachTo must name a built-in module in Order: $id"
            }
        }
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
        $name = 'pure-default'
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
            Write-Warning "upwsh theme: $($_.Exception.Message); keeping the previous theme or pure-default"
            $script:ThemeWarningStamp = $stamp
        }
        $theme = if ($script:ThemeCache) { $script:ThemeCache } else { Read-UpwshTheme 'pure-default' }
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
    $files = @{}
    foreach ($root in @($script:ThemeBundledRoot, $script:ThemeCustomRoot)) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json' -File) {
            $files[$file.BaseName] = $file.BaseName
        }
    }
    foreach ($name in @($files.Keys | Sort-Object)) {
        try {
            $theme = Read-UpwshTheme $name
            [pscustomobject]@{ Name = $theme.Name; Active = $theme.Name -ieq $active }
        } catch { Write-Warning "upwsh theme: skipping $name.json: $($_.Exception.Message)" }
    }
}

function Set-UpwshTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    # Fully validate before changing the reference; a bad theme cannot break the current prompt.
    $theme = Read-UpwshTheme $Name
    [void][IO.Directory]::CreateDirectory($script:ThemeCustomRoot)
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
