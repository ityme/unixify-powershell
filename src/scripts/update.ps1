# 更新 unixify-powershell：uninstall --keep-custom，再 install。custom 留下。
#   irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/update.ps1 | iex
#   pwsh -NoLogo -NoProfile -File src/scripts/update.ps1

$script:SavedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)
$script:DefaultRepo = 'ityme/unixify-powershell'

function Get-UpdateUsage {
    @'
usage: update.ps1 [-h | --help] [-c | --check]
                  [-p | --profile <path>] [--current-host]
                  [--ref <ref>] [--repo <owner/name>] [--source <dir>]

These are common update.ps1 commands used in various situations:

update this runtime
   --profile        pwsh profile to edit, default CurrentUserAllHosts
   --current-host   Write $PROFILE.CurrentUserCurrentHost
   --source         Local source tree, skip download
   --ref            Git branch or tag to download
   --repo           GitHub repository, default ityme/unixify-powershell

inspect without writing
   --check          Show uninstall --check, then stop

A network update can run:

  irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/update.ps1 | iex

Environment: UPWSH_REF UPWSH_REPO UPWSH_SOURCE
Update ~/.config/upwsh from the local project or a download. custom stays.
'@
}

function New-UpdateParseResult {
    [pscustomobject]@{
        Help          = $false
        Error         = $null
        Check         = $false
        UninstallArgs = @()
        InstallArgs   = @()
    }
}

function ConvertFrom-UpdateArguments {
    param([object[]]$Tokens)

    $tokens = @(
        $Tokens |
            Where-Object { $_ -ne $null -and [string]$_ -ne '' }
    )
    $result = New-UpdateParseResult
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
                $result.UninstallArgs += $token
                $result.InstallArgs += $token
                $index++
            }
            '^(--profile|-p)$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing profile path'
                    return $result
                }
                $value = [string]$tokens[$index + 1]
                $result.UninstallArgs += @($token, $value)
                $result.InstallArgs += @($token, $value)
                $index += 2
            }
            '^(--ref|--repo|--source)$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = "missing value for $token"
                    return $result
                }
                $result.InstallArgs += @($token, [string]$tokens[$index + 1])
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

function Get-LocalScriptRoot {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    if ($PSCommandPath) {
        return Split-Path -Parent $PSCommandPath
    }
    return $null
}

function Get-UpdateHome {
    [IO.Path]::GetFullPath((Join-Path $HOME '.config\upwsh'))
}

function Test-PathUnderHome {
    param([string]$Path, [string]$InstallHome)

    if (-not $Path -or -not $InstallHome) {
        return $false
    }
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $InstallHome.TrimEnd('\', '/') + '\'
    $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Complete-Update {
    param(
        [int]$Code,
        $Invocation = $MyInvocation
    )

    $ErrorActionPreference = $script:SavedErrorActionPreference
    $global:LASTEXITCODE = $Code
    if ($PSCommandPath -and $Invocation.CommandOrigin -eq 'Runspace') {
        exit $Code
    }
}

$parsed = ConvertFrom-UpdateArguments -Tokens $script:Arguments
$scriptInvocation = $MyInvocation
if ($parsed.Help) {
    if ($parsed.Error) {
        Write-Output "unixify-powershell: $($parsed.Error)"
        Write-Output ''
    }
    Get-UpdateUsage
    if ($parsed.Error) {
        Complete-Update 2 $scriptInvocation
        return
    }
    Complete-Update 0 $scriptInvocation
    return
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'unixify-powershell: need PowerShell 7'
    Complete-Update 1 $scriptInvocation
    return
}

if ($PSScriptRoot) {
    $relaunch = Join-Path $PSScriptRoot '_relaunch.ps1'
    if (Test-Path -LiteralPath $relaunch -PathType Leaf) {
        . $relaunch
    }
}
if (Get-Command Wait-UpwshRelaunchParent -ErrorAction SilentlyContinue) {
    Wait-UpwshRelaunchParent
}
$installHome = Get-UpdateHome
if (
    -not $parsed.Check -and
    (Get-Command Start-UpwshRelaunchIfNeeded -ErrorAction SilentlyContinue)
) {
    if (
        Start-UpwshRelaunchIfNeeded `
            -InstallHome $installHome `
            -EntryName 'update.ps1' `
            -Arguments $script:Arguments
    ) {
        Complete-Update 0 $scriptInvocation
        return
    }
}

$here = Get-LocalScriptRoot
$uninstall = $null
$install = $null
$tempUninstall = $null
$tempInstall = $null
if ($here) {
    $candidateUninstall = Join-Path $here 'uninstall.ps1'
    $candidateInstall = Join-Path $here 'install.ps1'
    if (Test-Path -LiteralPath $candidateUninstall -PathType Leaf) {
        $uninstall = $candidateUninstall
    }
    if (Test-Path -LiteralPath $candidateInstall -PathType Leaf) {
        $install = $candidateInstall
    }
}

$installHome = Get-UpdateHome
if ($install -and (Test-PathUnderHome -Path $install -InstallHome $installHome)) {
    $tempInstall = Join-Path ([IO.Path]::GetTempPath()) (
        'upwsh-install-' + [Guid]::NewGuid().ToString('N') + '.ps1'
    )
    Copy-Item -LiteralPath $install -Destination $tempInstall -Force
    $install = $tempInstall
}

if (-not $uninstall) {
    $tempUninstall = Join-Path ([IO.Path]::GetTempPath()) (
        'upwsh-uninstall-' + [Guid]::NewGuid().ToString('N') + '.ps1'
    )
    $raw = Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/$script:DefaultRepo/main/src/scripts/uninstall.ps1" `
        -UseBasicParsing
    [IO.File]::WriteAllText($tempUninstall, $raw.Content)
    $uninstall = $tempUninstall
}

$uninstallArgs = @('--keep-custom') + @($parsed.UninstallArgs)
if ($parsed.Check) {
    $uninstallArgs = @('--check', '--keep-custom') + @($parsed.UninstallArgs)
}

try {
    & $uninstall @uninstallArgs
    if ($parsed.Check) {
        Complete-Update $global:LASTEXITCODE $scriptInvocation
        return
    }
    if ($global:LASTEXITCODE -and $global:LASTEXITCODE -ne 0) {
        Complete-Update $global:LASTEXITCODE $scriptInvocation
        return
    }

    $env:UPWSH_HOME = $installHome

    if (-not $install) {
        $tempInstall = Join-Path ([IO.Path]::GetTempPath()) (
            'upwsh-install-' + [Guid]::NewGuid().ToString('N') + '.ps1'
        )
        $rawInstall = Invoke-WebRequest `
            -Uri "https://raw.githubusercontent.com/$script:DefaultRepo/main/src/scripts/install.ps1" `
            -UseBasicParsing
        [IO.File]::WriteAllText($tempInstall, $rawInstall.Content)
        $install = $tempInstall
    }
    $installArgs = @($parsed.InstallArgs)
    & $install @installArgs
    Complete-Update $global:LASTEXITCODE $scriptInvocation
} finally {
    if ($tempUninstall -and (Test-Path -LiteralPath $tempUninstall)) {
        Remove-Item -LiteralPath $tempUninstall -Force -ErrorAction SilentlyContinue
    }
    if ($tempInstall -and (Test-Path -LiteralPath $tempInstall)) {
        Remove-Item -LiteralPath $tempInstall -Force -ErrorAction SilentlyContinue
    }
}
