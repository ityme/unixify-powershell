# 让当前用户的 pwsh 加载本仓库。默认挂钩源码树里的 profile.ps1。
#   install_profile.ps1
#   install_profile.ps1 -Check
#   install_profile.ps1 -Uninstall
#   install_profile.ps1 -Deploy
#   install_profile.ps1 -CurrentHost

[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$Destination,
    [switch]$Check,
    [switch]$Uninstall,
    [switch]$Deploy,
    [switch]$CurrentHost
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\upwsh_home.ps1')
$script:NewLine = "`r`n"
$script:BeginMarker = '# >>> unixify-powershell >>>'
$script:EndMarker = '# <<< unixify-powershell <<<'

function Get-SourceRoot {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-SourceProfilePath {
    Join-Path (Get-SourceRoot) 'profile.ps1'
}

function Get-DefaultDestination {
    Get-UpwshHome
}

function Get-HookProfilePath {
    if ($ProfilePath) {
        return [IO.Path]::GetFullPath($ProfilePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:UPWSH_PROFILE)) {
        return [IO.Path]::GetFullPath((ConvertTo-UpwshWindowsPath $env:UPWSH_PROFILE))
    }
    if ($CurrentHost) {
        return $PROFILE.CurrentUserCurrentHost
    }
    return $PROFILE.CurrentUserAllHosts
}

function ConvertTo-SingleQuotedText {
    param([string]$Text)
    "'" + $Text.Replace("'", "''") + "'"
}

function Get-InstallBlock {
    param([string]$TargetProfile)

    $quoted = ConvertTo-SingleQuotedText $TargetProfile
    @(
        $script:BeginMarker
        "if (Test-Path -LiteralPath $quoted -PathType Leaf) {"
        "    . $quoted"
        '}'
        $script:EndMarker
    ) -join $script:NewLine
}

function Get-InstallPattern {
    '(?ms)^' + [regex]::Escape($script:BeginMarker) +
    '\r?\n.*?' + [regex]::Escape($script:EndMarker) +
    '(?:\r?\n)?'
}

function Read-ProfileText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    [IO.File]::ReadAllText($Path)
}

function Write-ProfileText {
    param([string]$Path, [string]$Text)

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text)
}

function Remove-InstallBlock {
    param([string]$Text)

    $removed = [regex]::Replace($Text, (Get-InstallPattern), '')
    $removed.TrimEnd() + $(if ($removed.Trim()) { $script:NewLine } else { '' })
}

function Set-InstallBlock {
    param([string]$Text, [string]$Block)

    $without = Remove-InstallBlock $Text
    if ([string]::IsNullOrWhiteSpace($without)) {
        return $Block + $script:NewLine
    }
    $without.TrimEnd() + $script:NewLine + $script:NewLine + $Block + $script:NewLine
}

function Get-InstalledTarget {
    param([string]$Text)

    $match = [regex]::Match($Text, (Get-InstallPattern))
    if (-not $match.Success) {
        return $null
    }
    if ($match.Value -match "LiteralPath '((?:''|[^'])*)'") {
        return $Matches[1].Replace("''", "'")
    }
    return $null
}

function Copy-CustomTree {
    param([string]$Source, [string]$Destination)

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force |
        ForEach-Object {
            $target = Join-Path $Destination $_.Name
            if (-not (Test-Path -LiteralPath $target)) {
                Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
            }
        }
}

function Copy-RuntimeTree {
    param([string]$Source, [string]$Destination)

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force |
        Where-Object { $_.Name -ne 'tests' } |
        ForEach-Object {
            if ($_.Name -eq 'custom') {
                Copy-CustomTree -Source $_.FullName -Destination (
                    Join-Path $Destination 'custom'
                )
            } else {
                Copy-Item -LiteralPath $_.FullName `
                    -Destination (Join-Path $Destination $_.Name) `
                    -Recurse -Force
            }
        }
    $custom = Join-Path $Destination 'custom'
    if (-not (Test-Path -LiteralPath $custom)) {
        New-Item -ItemType Directory -Path $custom -Force | Out-Null
    }
}

function Write-InstallStatus {
    param(
        [string]$HookPath,
        [string]$TargetPath,
        [string]$State
    )

    Write-Output ("profile  {0}" -f $HookPath)
    Write-Output ("target   {0}" -f $TargetPath)
    Write-Output ("state    {0}" -f $State)
}

if ($Uninstall -and $Deploy) {
    throw 'Use either -Uninstall or -Deploy, not both.'
}

$hookPath = Get-HookProfilePath
$sourceProfile = Get-SourceProfilePath
if (-not (Test-Path -LiteralPath $sourceProfile -PathType Leaf)) {
    throw "missing profile: $sourceProfile"
}

$targetProfile = $sourceProfile
if ($Deploy) {
    if (-not $Destination) {
        $Destination = Get-DefaultDestination
    }
    $Destination = [IO.Path]::GetFullPath($Destination)
    Copy-RuntimeTree -Source (Get-SourceRoot) -Destination $Destination
    $targetProfile = Join-Path $Destination 'profile.ps1'
}

$existing = Read-ProfileText $hookPath
$installedTarget = Get-InstalledTarget $existing

if ($Check) {
    $state = if ($installedTarget) { 'installed' } else { 'missing' }
    $shownTarget = if ($installedTarget) { $installedTarget } else { $targetProfile }
    Write-InstallStatus -HookPath $hookPath -TargetPath $shownTarget -State $state
    return
}

if ($Uninstall) {
    if (-not $installedTarget) {
        Write-InstallStatus -HookPath $hookPath -TargetPath $targetProfile -State 'missing'
        return
    }
    Write-ProfileText -Path $hookPath -Text (Remove-InstallBlock $existing)
    Write-InstallStatus -HookPath $hookPath -TargetPath $installedTarget -State 'removed'
    return
}

$updated = Set-InstallBlock -Text $existing -Block (Get-InstallBlock $targetProfile)
Write-ProfileText -Path $hookPath -Text $updated
$state = if ($Deploy) { 'deployed' } else { 'installed' }
Write-InstallStatus -HookPath $hookPath -TargetPath $targetProfile -State $state
