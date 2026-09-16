# 外部 CLI 适配和安装入口。

# 用途：把 top 转发给 bottom 的 btm 命令。
# 示例：top
function global:top {
    & btm @args
}

# 用途：把 du 转发给 dust；-s 或 -sh 显示目标汇总。
# 示例：du -sh /i/workspace
function global:du {
    try {
        $parsed = ConvertFrom-UnixArguments -Arguments @($args) -AllowedOptions @('s', 'h')
    } catch {
        $global:LASTEXITCODE = 2
        Write-Error $_
        return
    }

    $paths = @(ConvertTo-WindowsPathOperands $parsed.Operands)
    $dustArguments = @()

    if ($parsed.Options.Contains('s')) {
        $dustArguments += @('--depth', '0')
    }
    if ($paths.Count -gt 0) {
        $dustArguments += $paths
    }

    & dust @dustArguments
}

# 用途：安装常用 CLI。无参数、--help 或参数错误时显示用法。
# 示例：tools list
# 示例：tools install eza rg
# 示例：tools uninstall eza
function Get-ToolsUsage {
    @'
usage: tools [-h | --help] <command> [<name>...]

These are common tools commands used in various situations:

install listed CLI tools
   install          Download listed CLI tools; names limit the list
   uninstall        Remove the named tools from UPWSH_HOME\\tool\\bin
   list             List supported tools and whether the shell has them

'tools --help' prints this overview. uninstall requires names.

Listed tools: bat btm delta dust eza fd fzf hyperfine jq lazygit procs
rg shfmt starship tssh yazi yq zoxide
'@
}

function ConvertFrom-ToolsArguments {
    param([object[]]$Tokens)

    $action = ''
    $only = [Collections.Generic.List[string]]::new()
    $index = 0
    $tokens = @($Tokens)

    if ($tokens.Count -eq 0) {
        return [pscustomobject]@{ Help = $true; Error = $null }
    }

    $first = [string]$tokens[0]
    switch -Regex ($first) {
        '^(--help|-h)$' {
            return [pscustomobject]@{ Help = $true; Error = $null }
        }
        '^(--install|-i|install)$' {
            $action = 'install'
            $index = 1
        }
        '^(--uninstall|-u|uninstall)$' {
            $action = 'uninstall'
            $index = 1
        }
        '^(--list|list)$' {
            $action = 'list'
            $index = 1
        }
        default {
            $error = if ($first.StartsWith('-')) {
                "unknown option: $first"
            } else {
                "unknown tool command: $first"
            }
            return [pscustomobject]@{ Help = $true; Error = $error }
        }
    }

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        if ($token.StartsWith('-')) {
            return [pscustomobject]@{ Help = $true; Error = "unknown option: $token" }
        }
        $only.Add($token)
        $index++
    }

    if ($action -eq 'uninstall' -and $only.Count -eq 0) {
        return [pscustomobject]@{ Help = $true; Error = 'missing tool name' }
    }

    [pscustomobject]@{
        Help      = $false
        Error     = $null
        Action    = $action
        Only      = @($only)
    }
}

function global:tools {
    $parsed = ConvertFrom-ToolsArguments -Tokens $args
    if ($parsed.Help) {
        if ($parsed.Error) {
            Write-Output "tools: $($parsed.Error)"
            Write-Output ''
        }
        Get-ToolsUsage
        return
    }

    $installer = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot 'scripts\install_cli_tools.ps1')
    )
    $installerArgs = @{}
    if ($parsed.Only.Count -gt 0) {
        $installerArgs.Only = @($parsed.Only)
    }
    switch ($parsed.Action) {
        'list' {
            $installerArgs.List = $true
        }
        'uninstall' {
            $installerArgs.Uninstall = $true
        }
    }
    & $installer @installerArgs
}

Export-ModuleMember -Function @()

