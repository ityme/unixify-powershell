# upwsh：统一入口。reload 挂钩 pwsh profile，install 安装 CLI。
#   upwsh --help
#   upwsh -r
#   upwsh --reload --check
#   upwsh -i --check
#   upwsh --install -d /d/bin -o eza rg -f

$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)

function Get-UpwshUsage {
    @'
usage: upwsh [-h | --help]
             [-r | --reload | reload] [-i | --install | install]
             [-c | --check] [-u | --uninstall] [--deploy]
             [-d | --directory <dir>] [-p | --profile <path>]
             [--current-host] [-o | --only <name>...] [-f | --force]
             [<args>]

These are common upwsh commands used in various situations:

hook the current user's pwsh
   reload           Hook pwsh so it loads this runtime
   --check          Show hook status without writing files
   --uninstall      Remove the profile hook without deleting files
   --deploy         Copy the runtime to ~/.config/upwsh and hook that copy
   --directory      Runtime directory, default ~/.config/upwsh
   --profile        pwsh profile to edit, default CurrentUserAllHosts
   --current-host   Write $PROFILE.CurrentUserCurrentHost

install common CLI tools
   install          Download listed CLI tools into a directory
   --check          Show which listed tools are already installed
   --directory      Install directory, default I:\ityme\bin
   --only           Install only the named tools
   --force          Overwrite existing executables

'upwsh --help' prints this overview. reload and install cannot be used
together.

Listed tools: bat btm delta dust eza fd fzf hyperfine jq lazygit procs
rg shfmt starship tssh yazi yq zoxide
'@
}

function New-UpwshParseResult {
    param(
        [string]$Command = '',
        [switch]$Help,
        [string]$Error
    )

    [pscustomobject]@{
        Help        = [bool]$Help
        Error       = $Error
        Command     = $Command
        Check       = $false
        Uninstall   = $false
        Deploy      = $false
        CurrentHost = $false
        Force       = $false
        Directory   = $null
        Profile     = $null
        Only        = @()
    }
}

function ConvertFrom-UpwshArguments {
    param([object[]]$Tokens)

    $tokens = @(
        $Tokens |
            Where-Object { $_ -ne $null -and [string]$_ -ne '' }
    )
    $result = New-UpwshParseResult
    $index = 0

    if ($tokens.Count -eq 0) {
        $result.Help = $true
        return $result
    }

    $first = [string]$tokens[0]
    switch -Regex ($first) {
        '^(--help|-h)$' {
            $result.Help = $true
            return $result
        }
        '^(--reload|-r|reload)$' {
            $result.Command = 'reload'
            $index = 1
        }
        '^(--install|-i|install)$' {
            $result.Command = 'install'
            $index = 1
        }
        default {
            $result.Help = $true
            $result.Error = "unknown option: $first"
            return $result
        }
    }

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        switch -Regex ($token) {
            '^(--help|-h)$' {
                $result.Help = $true
                return $result
            }
            '^(--reload|-r|reload|--install|-i|install)$' {
                $result.Help = $true
                $result.Error = 'use either --reload or --install'
                return $result
            }
            '^(--check|-c)$' {
                $result.Check = $true
                $index++
            }
            '^(--uninstall|-u)$' {
                if ($result.Command -ne 'reload') {
                    $result.Help = $true
                    $result.Error = '--uninstall is only valid with --reload'
                    return $result
                }
                $result.Uninstall = $true
                $index++
            }
            '^--deploy$' {
                if ($result.Command -ne 'reload') {
                    $result.Help = $true
                    $result.Error = '--deploy is only valid with --reload'
                    return $result
                }
                $result.Deploy = $true
                $index++
            }
            '^--current-host$' {
                if ($result.Command -ne 'reload') {
                    $result.Help = $true
                    $result.Error = '--current-host is only valid with --reload'
                    return $result
                }
                $result.CurrentHost = $true
                $index++
            }
            '^(--force|-f)$' {
                if ($result.Command -ne 'install') {
                    $result.Help = $true
                    $result.Error = '--force is only valid with --install'
                    return $result
                }
                $result.Force = $true
                $index++
            }
            '^(--directory|-d)$' {
                $next = if ($index + 1 -lt $tokens.Count) { [string]$tokens[$index + 1] } else { '' }
                if ([string]::IsNullOrWhiteSpace($next) -or $next.StartsWith('-')) {
                    $result.Help = $true
                    $result.Error = 'missing directory'
                    return $result
                }
                $result.Directory = $next
                $index += 2
            }
            '^(--profile|-p)$' {
                if ($result.Command -ne 'reload') {
                    $result.Help = $true
                    $result.Error = '--profile is only valid with --reload'
                    return $result
                }
                $next = if ($index + 1 -lt $tokens.Count) { [string]$tokens[$index + 1] } else { '' }
                if ([string]::IsNullOrWhiteSpace($next) -or $next.StartsWith('-')) {
                    $result.Help = $true
                    $result.Error = 'missing profile path'
                    return $result
                }
                $result.Profile = $next
                $index += 2
            }
            '^(--only|-o)$' {
                if ($result.Command -ne 'install') {
                    $result.Help = $true
                    $result.Error = '--only is only valid with --install'
                    return $result
                }
                $index++
                $got = $false
                $only = [Collections.Generic.List[string]]::new()
                while (
                    $index -lt $tokens.Count -and
                    -not ([string]$tokens[$index]).StartsWith('-')
                ) {
                    $only.Add([string]$tokens[$index])
                    $got = $true
                    $index++
                }
                if (-not $got) {
                    $result.Help = $true
                    $result.Error = 'missing tool name'
                    return $result
                }
                $result.Only = @($only)
            }
            default {
                $result.Help = $true
                $result.Error = "unknown option: $token"
                return $result
            }
        }
    }

    if ($result.Command -eq 'reload') {
        if ($result.Uninstall -and $result.Deploy) {
            $result.Help = $true
            $result.Error = 'use either --uninstall or --deploy'
            return $result
        }
        if ($result.Directory -and -not $result.Deploy) {
            $result.Help = $true
            $result.Error = '--directory is only valid with --deploy'
            return $result
        }
    }

    return $result
}

function ConvertTo-WindowsStyleDirectory {
    param([string]$Path)

    if (Get-Command ConvertTo-WindowsStyleText -ErrorAction SilentlyContinue) {
        return ConvertTo-WindowsStyleText $Path
    }

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

function Invoke-UpwshReload {
    param($Parsed)

    $installer = Join-Path $PSScriptRoot 'install_profile.ps1'
    $installerArgs = @{}
    if ($Parsed.Profile) {
        $installerArgs.ProfilePath = ConvertTo-WindowsStyleDirectory $Parsed.Profile
    }
    if ($Parsed.Directory) {
        $installerArgs.Destination = ConvertTo-WindowsStyleDirectory $Parsed.Directory
    }
    if ($Parsed.Check) {
        $installerArgs.Check = $true
    }
    if ($Parsed.Uninstall) {
        $installerArgs.Uninstall = $true
    }
    if ($Parsed.Deploy) {
        $installerArgs.Deploy = $true
    }
    if ($Parsed.CurrentHost) {
        $installerArgs.CurrentHost = $true
    }
    & $installer @installerArgs
}

function Invoke-UpwshInstall {
    param($Parsed)

    $installer = Join-Path $PSScriptRoot 'install_cli_tools.ps1'
    $installerArgs = @{}
    if ($Parsed.Directory) {
        $installerArgs.Dir = ConvertTo-WindowsStyleDirectory $Parsed.Directory
    }
    if ($Parsed.Only.Count -gt 0) {
        $installerArgs.Only = @($Parsed.Only)
    }
    if ($Parsed.Check) {
        $installerArgs.Check = $true
    }
    if ($Parsed.Force) {
        $installerArgs.Force = $true
    }
    & $installer @installerArgs
}

function Complete-Upwsh {
    param(
        [int]$Code,
        $Invocation = $MyInvocation
    )

    $global:LASTEXITCODE = $Code
    if ($Invocation.CommandOrigin -eq 'Runspace') {
        exit $Code
    }
}

$parsed = ConvertFrom-UpwshArguments -Tokens $script:Arguments
$scriptInvocation = $MyInvocation
if ($parsed.Help -or -not $parsed.Command) {
    if ($parsed.Error) {
        Write-Output "upwsh: $($parsed.Error)"
        Write-Output ''
    }
    Get-UpwshUsage
    if ($parsed.Error) {
        Complete-Upwsh 2 $scriptInvocation
        return
    }
    Complete-Upwsh 0 $scriptInvocation
    return
}

if ($parsed.Command -eq 'reload') {
    Invoke-UpwshReload -Parsed $parsed
    Complete-Upwsh 0 $scriptInvocation
    return
}

Invoke-UpwshInstall -Parsed $parsed
Complete-Upwsh 0 $scriptInvocation
