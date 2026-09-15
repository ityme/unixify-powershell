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
# 示例：tools -c -d /d/bin -o eza rg -f
function Get-ToolsUsage {
    @'
usage: tools [-h | --help] [-c | --check] [-d | --directory <dir>]
             [-o | --only <name>...] [-f | --force]

These are common tools commands used in various situations:

install listed CLI tools
   --check          Show which listed tools are already installed
   --directory      Install directory, default I:\ityme\bin
   --only           Install only the named tools
   --force          Overwrite existing executables

'tools --help' prints this overview.

Listed tools: bat btm delta dust eza fd fzf hyperfine jq lazygit procs
rg shfmt starship tssh yazi yq zoxide
'@
}

function ConvertFrom-ToolsArguments {
    param([object[]]$Tokens)

    $check = $false
    $force = $false
    $dir = $null
    $only = [Collections.Generic.List[string]]::new()
    $index = 0
    $tokens = @($Tokens)

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        switch -Regex ($token) {
            '^(--help|-h)$' {
                return [pscustomobject]@{ Help = $true; Error = $null }
            }
            '^(--check|-c)$' {
                $check = $true
                $index++
            }
            '^(--force|-f)$' {
                $force = $true
                $index++
            }
            '^(--directory|-d)$' {
                $next = if ($index + 1 -lt $tokens.Count) { [string]$tokens[$index + 1] } else { '' }
                if ([string]::IsNullOrWhiteSpace($next) -or $next.StartsWith('-')) {
                    return [pscustomobject]@{ Help = $true; Error = 'missing directory' }
                }
                $dir = $next
                $index += 2
            }
            '^(--only|-o)$' {
                $index++
                $got = $false
                while (
                    $index -lt $tokens.Count -and
                    -not ([string]$tokens[$index]).StartsWith('-')
                ) {
                    $only.Add([string]$tokens[$index])
                    $got = $true
                    $index++
                }
                if (-not $got) {
                    return [pscustomobject]@{ Help = $true; Error = 'missing tool name' }
                }
            }
            default {
                return [pscustomobject]@{ Help = $true; Error = "unknown option: $token" }
            }
        }
    }

    [pscustomobject]@{
        Help  = $false
        Error = $null
        Check = $check
        Force = $force
        Dir   = $dir
        Only  = @($only)
    }
}

function global:tools {
    $parsed = ConvertFrom-ToolsArguments -Tokens $args
    if ($args.Count -eq 0 -or $parsed.Help) {
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
    if ($parsed.Dir) {
        $installerArgs.Dir = ConvertTo-WindowsStyleText $parsed.Dir
    }
    if ($parsed.Only.Count -gt 0) {
        $installerArgs.Only = @($parsed.Only)
    }
    if ($parsed.Check) {
        $installerArgs.Check = $true
    }
    if ($parsed.Force) {
        $installerArgs.Force = $true
    }
    & $installer @installerArgs
}

Export-ModuleMember -Function @()
