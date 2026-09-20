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
#   upwsh theme list
#   upwsh theme install pure-default

$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)

function Get-UpwshUsage {
    @'
usage: upwsh [-h | --help] <command> [<args>]

These are common upwsh commands used in various situations:

hook the current user's pwsh
   load             Enable startup loading; load this pwsh when called in-process
   unload           Stop $PROFILE from loading it; leave files, Path, and upwsh

install this runtime
   install          Install or repair ~/.config/upwsh; first install enables loading
   uninstall        Unload, drop UPWSH_HOME and Path, then delete the install tree
   update           Update installed files; keep custom, tools, and startup loading state

install a listed CLI tool
   tool install     Download listed CLI tools; names limit the list
   tool uninstall   Remove the named tools from UPWSH_HOME\\tool\\bin
   tool list        List supported tools and whether the shell has them

select a local prompt theme
   theme list       List installed themes; * marks the active theme
   theme install    Select a local theme by name and refresh the prompt

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
        '^theme$' {
            $result.Command = 'theme'
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

    if ($result.Command -eq 'theme') {
        $rest = @($tokens | Select-Object -Skip 1)
        if ($rest.Count -eq 1 -and $rest[0] -in @('-h', '--help')) {
            $result.Help = $true
        } elseif ($rest.Count -eq 1 -and $rest[0] -eq 'list') {
            $result.Action = 'list'
        } elseif ($rest.Count -eq 2 -and $rest[0] -eq 'install' -and -not $rest[1].StartsWith('-')) {
            $result.Action = 'install'
            $result.Only = @([string]$rest[1])
        } else {
            $result.Help = $true
            $result.Error = 'usage: upwsh theme list | upwsh theme install <name>'
        }
        return $result
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
    if ($env:UPWSH_SKIP_SESSION_LOAD -or $scriptInvocation.CommandOrigin -eq 'Runspace') {
        Write-Output 'Open a new pwsh to load the runtime.'
        return
    }
    $runtimeProfile = Join-Path (Get-UpwshHome) 'profile.ps1'
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

function Invoke-UpwshTheme {
    param($Parsed)

    . (Join-Path $PSScriptRoot '..\upwsh_home.ps1')
    $themePath = Join-Path (Get-UpwshHome) 'theme.psm1'
    if (-not [IO.File]::Exists($themePath)) { throw 'themes are not installed; run upwsh install first' }
    $module = Import-Module $themePath -Global -PassThru -ErrorAction Stop
    if ($Parsed.Action -eq 'list') {
        foreach ($theme in @(& $module { Get-UpwshThemeList })) {
            $mark = if ($theme.Active) { '*' } else { ' ' }
            Write-Output "$mark $($theme.Name)"
        }
    } else {
        $selected = & $module { param($name) Set-UpwshTheme $name } $Parsed.Only[0]
        Write-Output "theme    $selected"
    }
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
    if ($PSCommandPath -and $Invocation.CommandOrigin -eq 'Runspace') {
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

if ($parsed.Command -eq 'theme') {
    try {
        Invoke-UpwshTheme -Parsed $parsed
    } catch {
        Write-Output "upwsh: $($_.Exception.Message)"
        Complete-Upwsh 1 $scriptInvocation
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
