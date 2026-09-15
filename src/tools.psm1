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
tools  安装常用 CLI 到指定目录（默认 I:\ityme\bin）

用法:
  tools
  tools --help
  tools -c
  tools --check
  tools -d /d/bin
  tools --directory /d/bin
  tools -o eza rg
  tools --only eza rg
  tools -f
  tools --force
  tools -c -d /d/bin -o eza rg -f

选项:
  -c, --check         只查看哪些已安装
  -d, --directory DIR 安装目录，可用 /d/bin
  -o, --only NAME...  只装列出的工具
  -f, --force         覆盖已有 exe
  -h, --help          显示本说明

清单: bat btm delta dust eza fd fzf hyperfine jq lazygit procs rg shfmt starship tssh yazi yq zoxide
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
