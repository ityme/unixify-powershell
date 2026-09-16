# upwsh：统一入口。load / unload 挂钩 profile；install / uninstall / update 管安装树。
#   upwsh --help
#   upwsh load
#   upwsh unload
#   upwsh install
#   upwsh uninstall
#   upwsh update
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
   load             Hook pwsh so it loads this runtime; set UPWSH_HOME, append bin paths, and load it now
   unload           Remove the profile hook; leave UPWSH_HOME and Path in place

install this runtime
   install          Copy the runtime to UPWSH_HOME and load it
   uninstall        Unload, drop UPWSH_HOME and Path, then delete the install tree
   update           Uninstall --keep-custom, then install

install a listed CLI tool
   tool install     Download listed CLI tools; names limit the list
   tool uninstall   Remove the named tools from UPWSH_HOME\\tool\\bin
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
        Rest    = @()
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
        '^install$' {
            $result.Command = 'install'
            $index = 1
        }
        '^uninstall$' {
            $result.Command = 'uninstall'
            $index = 1
        }
        '^update$' {
            $result.Command = 'update'
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

    if ($result.Command -in @('install', 'uninstall', 'update')) {
        while ($index -lt $tokens.Count) {
            $result.Rest = @($result.Rest + [string]$tokens[$index])
            $index++
        }
        return $result
    }

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        switch -Regex ($token) {
            '^(--help|-h)$' {
                $result.Help = $true
                return $result
            }
            '^(--load|-l|load|--unload|unload|--tool|-t|tool|install|uninstall|update)$' {
                $result.Help = $true
                $result.Error = 'use only one of load, unload, tool, install, uninstall, or update'
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
    if ($Parsed.Command -eq 'unload') {
        return
    }
    . (Join-Path $PSScriptRoot '..\upwsh_home.ps1')
    Add-UpwshUserEnvironment
    if ($env:UPWSH_SKIP_SESSION_LOAD) {
        return
    }
    $runtimeProfile = Join-Path $PSScriptRoot '..\profile.ps1'
    if (Test-Path -LiteralPath $runtimeProfile -PathType Leaf) {
        . $runtimeProfile
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

function Invoke-UpwshSetup {
    param($Parsed)

    $script = Join-Path $PSScriptRoot "$($Parsed.Command).ps1"
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "missing $($Parsed.Command) script: $script"
    }
    $setupArgs = @($Parsed.Rest)
    & $script @setupArgs
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

if ($parsed.Command -in @('install', 'uninstall', 'update')) {
    Invoke-UpwshSetup -Parsed $parsed
    Complete-Upwsh $global:LASTEXITCODE $scriptInvocation
    return
}

Invoke-UpwshTool -Parsed $parsed
Complete-Upwsh 0 $scriptInvocation
