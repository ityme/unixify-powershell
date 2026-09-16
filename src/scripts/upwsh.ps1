# upwsh：统一入口。load / unload 挂钩 pwsh profile，tool 安装 CLI。
#   upwsh --help
#   upwsh load
#   upwsh unload
#   upwsh tool list
#   upwsh tool install eza rg
#   upwsh tool uninstall eza

$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)

function Get-UpwshUsage {
    @'
usage: upwsh [-h | --help] <command> [<args>]

These are common upwsh commands used in various situations:

hook the current user's pwsh
   load             Hook pwsh so it loads this runtime; add UPWSH_HOME\\bin to the user Path if missing
   unload           Remove the profile hook without deleting files

install a listed CLI tool
   tool install     Download listed CLI tools; names limit the list
   tool uninstall   Remove the named tools from UPWSH_HOME\\bin
   tool list        List supported tools and whether the shell has them

'upwsh --help' prints this overview.

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
        Help    = [bool]$Help
        Error   = $Error
        Command = $Command
        Action  = ''
        Only    = @()
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
        '^(--unload|unload)$' {
            $result.Command = 'unload'
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

    if ($result.Command -eq 'tool') {
        if ($index -ge $tokens.Count) {
            $result.Help = $true
            $result.Error = 'missing tool command'
            return $result
        }
        $action = [string]$tokens[$index]
        switch -Regex ($action) {
            '^(--help|-h)$' {
                $result.Help = $true
                return $result
            }
            '^(--install|-i|install)$' {
                $result.Action = 'install'
            }
            '^(--uninstall|-u|uninstall)$' {
                $result.Action = 'uninstall'
            }
            '^(--list|list)$' {
                $result.Action = 'list'
            }
            default {
                $result.Help = $true
                $result.Error = "unknown tool command: $action"
                return $result
            }
        }
        $index++
    }

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        switch -Regex ($token) {
            '^(--help|-h)$' {
                $result.Help = $true
                return $result
            }
            '^(--load|-l|load|--unload|unload|--tool|-t|tool)$' {
                $result.Help = $true
                $result.Error = 'use only one of load, unload, or tool'
                return $result
            }
            default {
                if ($result.Command -eq 'tool' -and -not $token.StartsWith('-')) {
                    $result.Only = @($result.Only + $token)
                    $index++
                } else {
                    $result.Help = $true
                    $result.Error = "unknown option: $token"
                    return $result
                }
            }
        }
    }

    if ($result.Command -eq 'tool' -and $result.Action -eq 'uninstall' -and $result.Only.Count -eq 0) {
        $result.Help = $true
        $result.Error = 'missing tool name'
        return $result
    }

    return $result
}

function Invoke-UpwshLoad {
    param($Parsed)

    $installer = Join-Path $PSScriptRoot 'install_profile.ps1'
    $installerArgs = @{}
    if ($Parsed.Command -eq 'unload') {
        $installerArgs.Uninstall = $true
    }
    & $installer @installerArgs
    if ($Parsed.Command -eq 'load') {
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
    switch ($Parsed.Action) {
        'list' {
            $installerArgs.List = $true
        }
        'uninstall' {
            $installerArgs.Uninstall = $true
        }
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

if ($parsed.Command -in @('load', 'unload')) {
    Invoke-UpwshLoad -Parsed $parsed
    Complete-Upwsh 0 $scriptInvocation
    return
}

Invoke-UpwshTool -Parsed $parsed
Complete-Upwsh 0 $scriptInvocation
