# 卸掉 unixify-powershell：先 unload，再删安装目录。
#   irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/uninstall.ps1 | iex
#   pwsh -NoLogo -NoProfile -File src/scripts/uninstall.ps1

$script:SavedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)
$script:BeginMarker = '# >>> unixify-powershell >>>'
$script:EndMarker = '# <<< unixify-powershell <<<'

function Get-UninstallUsage {
    @'
usage: uninstall.ps1 [-h | --help] [-c | --check]
                     [-p | --profile <path>] [--current-host]
                     [--keep-custom]

These are common uninstall.ps1 commands used in various situations:

remove this runtime
   --profile        pwsh profile to edit, default CurrentUserAllHosts
   --current-host   Write $PROFILE.CurrentUserCurrentHost
   --keep-custom    Keep UPWSH_HOME\\custom when deleting the install tree

inspect without writing
   --check          Show what would be removed

A network uninstall can run:

  irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/uninstall.ps1 | iex

Environment: UPWSH_HOME
Unload first, then drop UPWSH_HOME and Path, then delete the install tree.
--keep-custom leaves UPWSH_HOME\\custom in place.
'@
}

function New-UninstallParseResult {
    [pscustomobject]@{
        Help        = $false
        Error       = $null
        Check       = $false
        CurrentHost = $false
        KeepCustom  = $false
        Profile     = $null
    }
}

function ConvertFrom-UninstallArguments {
    param([object[]]$Tokens)

    $tokens = @(
        $Tokens |
            Where-Object { $_ -ne $null -and [string]$_ -ne '' }
    )
    $result = New-UninstallParseResult
    $index = 0

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        switch -Regex ($token) {
            '^(--help|-h)$' {
                $result.Help = $true
                return $result
            }
            '^(--check|-c)$' {
                $result.Check = $true
                $index++
            }
            '^--current-host$' {
                $result.CurrentHost = $true
                $index++
            }
            '^--keep-custom$' {
                $result.KeepCustom = $true
                $index++
            }
            '^(--profile|-p)$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing profile path'
                    return $result
                }
                $result.Profile = [string]$tokens[$index + 1]
                $index += 2
            }
            default {
                $result.Help = $true
                $result.Error = "unknown option: $token"
                return $result
            }
        }
    }

    return $result
}

function ConvertTo-WindowsStyleDirectory {
    param([string]$Path)

    $windows = $Path
    $homePath = ($HOME.TrimEnd('\', '/') -replace '\\', '/')
    $windows = [regex]::Replace($windows, '(?<=^|[\s=''"])~(?=/|$|\\)', $homePath)
    $windows = [regex]::Replace(
        $windows,
        '/([A-Za-z]):',
        { param($m) $m.Groups[1].Value.ToUpperInvariant() + ':' }
    )
    return [regex]::Replace(
        $windows,
        '(?<=^|[\s=''"])/([A-Za-z])(/|$)',
        { param($m) $m.Groups[1].Value.ToUpperInvariant() + ':/' }
    )
}

function Get-UninstallHome {
    $raw = $env:UPWSH_HOME
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [Environment]::GetEnvironmentVariable('UPWSH_HOME', 'User')
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = Join-Path $HOME '.config\upwsh'
    } else {
        $raw = ConvertTo-WindowsStyleDirectory $raw
    }
    [IO.Path]::GetFullPath($raw)
}

function Get-UninstallHookPath {
    param($Parsed)

    if ($Parsed.Profile) {
        return [IO.Path]::GetFullPath(
            (ConvertTo-WindowsStyleDirectory $Parsed.Profile)
        )
    }
    if ($Parsed.CurrentHost) {
        return $PROFILE.CurrentUserCurrentHost
    }
    if (-not [string]::IsNullOrWhiteSpace($env:UPWSH_PROFILE)) {
        return [IO.Path]::GetFullPath(
            (ConvertTo-WindowsStyleDirectory $env:UPWSH_PROFILE)
        )
    }
    $PROFILE.CurrentUserAllHosts
}

function Test-GitCheckout {
    param([string]$Path)

    if (Test-Path -LiteralPath (Join-Path $Path '.git')) {
        return $true
    }
    $leaf = Split-Path -Leaf $Path
    $parent = Split-Path -Parent $Path
    if ($leaf -eq 'src' -and $parent -and (Test-Path -LiteralPath (Join-Path $parent '.git'))) {
        return $true
    }
    return $false
}

function Test-ProfileHook {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $text = [IO.File]::ReadAllText($Path)
    $text.Contains($script:BeginMarker)
}

function Remove-ProfileHookFallback {
    param([string]$Path)

    if (-not (Test-ProfileHook $Path)) {
        return
    }
    $pattern = '(?ms)^' + [regex]::Escape($script:BeginMarker) +
        '\r?\n.*?' + [regex]::Escape($script:EndMarker) +
        '(?:\r?\n)?'
    $text = [IO.File]::ReadAllText($Path)
    $removed = [regex]::Replace($text, $pattern, '')
    $removed = $removed.TrimEnd() + $(if ($removed.Trim()) { "`r`n" } else { '' })
    [IO.File]::WriteAllText($Path, $removed)
    Write-Output ("profile  {0}" -f $Path)
    Write-Output 'state    removed'
}

function Complete-Uninstall {
    param(
        [int]$Code,
        $Invocation = $MyInvocation
    )

    $ErrorActionPreference = $script:SavedErrorActionPreference
    $global:LASTEXITCODE = $Code
    if (-not $PSCommandPath -or $Invocation.CommandOrigin -eq 'Runspace') {
        exit $Code
    }
}

$parsed = ConvertFrom-UninstallArguments -Tokens $script:Arguments
$scriptInvocation = $MyInvocation
if ($parsed.Help) {
    if ($parsed.Error) {
        Write-Output "unixify-powershell: $($parsed.Error)"
        Write-Output ''
    }
    Get-UninstallUsage
    if ($parsed.Error) {
        Complete-Uninstall 2 $scriptInvocation
        return
    }
    Complete-Uninstall 0 $scriptInvocation
    return
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'unixify-powershell: need PowerShell 7'
    Complete-Uninstall 1 $scriptInvocation
    return
}

$directory = Get-UninstallHome
$hookPath = Get-UninstallHookPath -Parsed $parsed
$upwsh = Join-Path $directory 'scripts\upwsh.ps1'
$homeScript = Join-Path $directory 'upwsh_home.ps1'
$keepTree = Test-GitCheckout $directory
$relaunch = Join-Path $PSScriptRoot '_relaunch.ps1'
if (Test-Path -LiteralPath $relaunch -PathType Leaf) {
    . $relaunch
}
if (Get-Command Wait-UpwshRelaunchParent -ErrorAction SilentlyContinue) {
    Wait-UpwshRelaunchParent
}

if (
    -not $parsed.Check -and
    (Get-Command Start-UpwshRelaunchIfNeeded -ErrorAction SilentlyContinue)
) {
    if (
        Start-UpwshRelaunchIfNeeded `
            -InstallHome $directory `
            -EntryName 'uninstall.ps1' `
            -Arguments $script:Arguments
    ) {
        Complete-Uninstall 0 $scriptInvocation
        return
    }
}

if (
    -not $parsed.Check -and
    $PSCommandPath -and
    -not $env:UPWSH_UNINSTALL_REEXEC -and
    -not $env:UPWSH_SKIP_RELAUNCH -and
    (Get-Command Test-UpwshPathUnder -ErrorAction SilentlyContinue) -and
    (Test-UpwshPathUnder -Path $PSCommandPath -Root $directory)
) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) (
        'upwsh-uninstall-' + [Guid]::NewGuid().ToString('N') + '.ps1'
    )
    Copy-Item -LiteralPath $PSCommandPath -Destination $temp -Force
    $savedReexec = $env:UPWSH_UNINSTALL_REEXEC
    try {
        $env:UPWSH_UNINSTALL_REEXEC = '1'
        & $temp @script:Arguments
        Complete-Uninstall $global:LASTEXITCODE $scriptInvocation
        return
    } finally {
        $env:UPWSH_UNINSTALL_REEXEC = $savedReexec
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ("home     {0}" -f $directory)
Write-Output ("profile  {0}" -f $hookPath)
if ($parsed.Check) {
    $state = if (Test-ProfileHook $hookPath) { 'installed' } else { 'missing' }
    Write-Output ("hook     {0}" -f $state)
    $treeState = if (Test-Path -LiteralPath $directory) { 'present' } else { 'missing' }
    if ($keepTree -and $treeState -eq 'present') {
        $treeState = 'kept'
    }
    Write-Output ("tree     {0}" -f $treeState)
    if ($parsed.KeepCustom) {
        Write-Output 'custom   keep'
    }
    Complete-Uninstall 0 $scriptInvocation
    return
}

$savedProfile = $env:UPWSH_PROFILE
try {
    $env:UPWSH_PROFILE = $hookPath
    $env:UPWSH_HOME = $directory
    if (Test-Path -LiteralPath $upwsh -PathType Leaf) {
        & $upwsh unload
    } else {
        Remove-ProfileHookFallback -Path $hookPath
    }
    if (Test-Path -LiteralPath $homeScript -PathType Leaf) {
        . $homeScript
        Remove-UpwshUserEnvironment
    }
} finally {
    $env:UPWSH_PROFILE = $savedProfile
}

if (Test-ProfileHook $hookPath) {
    Remove-ProfileHookFallback -Path $hookPath
}

if ($keepTree) {
    Write-Output ("tree     kept {0}" -f $directory)
} elseif (Test-Path -LiteralPath $directory) {
    $custom = Join-Path $directory 'custom'
    $savedCustom = $null
    if ($parsed.KeepCustom -and (Test-Path -LiteralPath $custom)) {
        $savedCustom = Join-Path ([IO.Path]::GetTempPath()) (
            'upwsh-custom-' + [Guid]::NewGuid().ToString('N')
        )
        Move-Item -LiteralPath $custom -Destination $savedCustom
    }
    if (Get-Command Remove-UpwshTree -ErrorAction SilentlyContinue) {
        Remove-UpwshTree -Path $directory
    } else {
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
    Write-Output ("tree     removed {0}" -f $directory)
    if ($savedCustom) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Move-Item -LiteralPath $savedCustom -Destination $custom
        Write-Output ("custom   kept {0}" -f $custom)
    }
}

Complete-Uninstall 0 $scriptInvocation
