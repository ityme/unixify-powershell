# upwsh：统一入口。load 挂钩 pwsh profile，tool 安装 CLI。
#   upwsh --help
#   upwsh load
#   upwsh --load --check
#   upwsh -t --check
#   upwsh --tool --install eza rg
#   upwsh --tool --uninstall eza

$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)

function Get-UpwshUsage {
    @'
usage: upwsh [-h | --help]
             [-l | --load | load] [-t | --tool | tool]
             [-c | --check] [-i | --install] [-u | --uninstall] [--deploy]
             [-p | --profile <path>]
             [--current-host] [-o | --only <name>...] [-f | --force]
             [<args>]

These are common upwsh commands used in various situations:

hook the current user's pwsh
   load             Hook pwsh so it loads this runtime
   --check          Show hook status without writing files
   --uninstall      Remove the profile hook without deleting files
   --deploy         Copy the runtime to UPWSH_HOME and hook that copy
   --profile        pwsh profile to edit, default CurrentUserAllHosts
   --current-host   Write $PROFILE.CurrentUserCurrentHost

install a listed CLI tool
   tool             Download or remove listed CLI tools
   --install        Install the named tools; with no names, install the list
   --uninstall      Remove the named tools from UPWSH_HOME\\bin
   --check          Show which listed tools are already installed
   --only           Same as naming tools after --install
   --force          Overwrite existing executables

'upwsh --help' prints this overview. load and tool cannot be used
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
        Install     = $false
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
        '^(--load|-l|load)$' {
            $result.Command = 'load'
            $index = 1
        }
        '^(--tool|-t|tool)$' {
            $result.Command = 'tool'
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
            '^(--load|-l|load|--tool|-t|tool)$' {
                $result.Help = $true
                $result.Error = 'use either --load or --tool'
                return $result
            }
            '^(--check|-c)$' {
                $result.Check = $true
                $index++
            }
            '^(--install|-i)$' {
                if ($result.Command -ne 'tool') {
                    $result.Help = $true
                    $result.Error = '--install is only valid with --tool'
                    return $result
                }
                $result.Install = $true
                $index++
                while (
                    $index -lt $tokens.Count -and
                    -not ([string]$tokens[$index]).StartsWith('-')
                ) {
                    $result.Only = @($result.Only + [string]$tokens[$index])
                    $index++
                }
            }
            '^(--uninstall|-u)$' {
                if ($result.Command -notin @('load', 'tool')) {
                    $result.Help = $true
                    $result.Error = '--uninstall is only valid with --load or --tool'
                    return $result
                }
                $result.Uninstall = $true
                $index++
                if ($result.Command -eq 'tool') {
                    while (
                        $index -lt $tokens.Count -and
                        -not ([string]$tokens[$index]).StartsWith('-')
                    ) {
                        $result.Only = @($result.Only + [string]$tokens[$index])
                        $index++
                    }
                }
            }
            '^--deploy$' {
                if ($result.Command -ne 'load') {
                    $result.Help = $true
                    $result.Error = '--deploy is only valid with --load'
                    return $result
                }
                $result.Deploy = $true
                $index++
            }
            '^--current-host$' {
                if ($result.Command -ne 'load') {
                    $result.Help = $true
                    $result.Error = '--current-host is only valid with --load'
                    return $result
                }
                $result.CurrentHost = $true
                $index++
            }
            '^(--force|-f)$' {
                if ($result.Command -ne 'tool') {
                    $result.Help = $true
                    $result.Error = '--force is only valid with --tool'
                    return $result
                }
                $result.Force = $true
                $index++
            }
            '^(--profile|-p)$' {
                if ($result.Command -ne 'load') {
                    $result.Help = $true
                    $result.Error = '--profile is only valid with --load'
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
                if ($result.Command -ne 'tool') {
                    $result.Help = $true
                    $result.Error = '--only is only valid with --tool'
                    return $result
                }
                $index++
                $got = $false
                while (
                    $index -lt $tokens.Count -and
                    -not ([string]$tokens[$index]).StartsWith('-')
                ) {
                    $result.Only = @($result.Only + [string]$tokens[$index])
                    $got = $true
                    $index++
                }
                if (-not $got) {
                    $result.Help = $true
                    $result.Error = 'missing tool name'
                    return $result
                }
            }
            default {
                $result.Help = $true
                $result.Error = "unknown option: $token"
                return $result
            }
        }
    }

    if ($result.Command -eq 'load') {
        if ($result.Uninstall -and $result.Deploy) {
            $result.Help = $true
            $result.Error = 'use either --uninstall or --deploy'
            return $result
        }
    }

    if ($result.Command -eq 'tool') {
        if ($result.Install -and $result.Uninstall) {
            $result.Help = $true
            $result.Error = 'use either --install or --uninstall'
            return $result
        }
        if ($result.Uninstall -and $result.Only.Count -eq 0) {
            $result.Help = $true
            $result.Error = 'missing tool name'
            return $result
        }
        if ($result.Force -and $result.Uninstall) {
            $result.Help = $true
            $result.Error = '--force is only valid with --install'
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

function Invoke-UpwshLoad {
    param($Parsed)

    $installer = Join-Path $PSScriptRoot 'install_profile.ps1'
    $installerArgs = @{}
    if ($Parsed.Profile) {
        $installerArgs.ProfilePath = ConvertTo-WindowsStyleDirectory $Parsed.Profile
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
    if ($Parsed.Deploy) {
        . (Join-Path $PSScriptRoot '..\upwsh_home.ps1')
        Add-UpwshBinToUserPath
    }
}

function Invoke-UpwshTool {
    param($Parsed)

    $installer = Join-Path $PSScriptRoot 'install_cli_tools.ps1'
    $installerArgs = @{}
    if ($Parsed.Only.Count -gt 0) {
        $installerArgs.Only = @($Parsed.Only)
    }
    if ($Parsed.Check) {
        $installerArgs.Check = $true
    }
    if ($Parsed.Force) {
        $installerArgs.Force = $true
    }
    if ($Parsed.Uninstall) {
        $installerArgs.Uninstall = $true
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

if ($parsed.Command -eq 'load') {
    Invoke-UpwshLoad -Parsed $parsed
    Complete-Upwsh 0 $scriptInvocation
    return
}

Invoke-UpwshTool -Parsed $parsed
Complete-Upwsh 0 $scriptInvocation
