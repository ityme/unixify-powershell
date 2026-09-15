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
upwsh  统一入口：挂钩 pwsh profile，或安装常用 CLI

用法:
  upwsh
  upwsh --help
  upwsh -r
  upwsh --reload
  upwsh reload
  upwsh -r --check
  upwsh --reload --uninstall
  upwsh --reload --deploy
  upwsh --reload --deploy -d ~/.config/pwsh
  upwsh --reload --current-host
  upwsh --reload --profile PATH
  upwsh -i
  upwsh --install
  upwsh install
  upwsh -i --check
  upwsh --install -d /d/bin
  upwsh --install -o eza rg
  upwsh --install -c -d /d/bin -o eza rg -f

动作:
  -r, --reload, reload    挂钩当前用户的 pwsh，相当于 scripts/install_profile.ps1
  -i, --install, install  安装常用 CLI，相当于 scripts/install_cli_tools.ps1
  -h, --help              显示本说明

  无参数或 --help 显示本说明。-r 和 -i 不能同时用。

reload 选项:
  -c, --check             只查看挂钩状态，不写文件
  -u, --uninstall         去掉挂钩标记块
      --deploy            先把运行时拷到目标目录（不含 tests），再挂钩那份副本
  -d, --directory DIR     --deploy 的目标目录，默认 ~/.config/pwsh
      --current-host      写 $PROFILE.CurrentUserCurrentHost
                          默认写 $PROFILE.CurrentUserAllHosts
  -p, --profile PATH      指定要改的 profile 文件

install 选项:
  -c, --check             只查看哪些 CLI 已安装
  -d, --directory DIR     安装目录，默认 I:\ityme\bin，可用 /d/bin
  -o, --only NAME...      只装列出的工具
  -f, --force             覆盖已有 exe

清单: bat btm delta dust eza fd fzf hyperfine jq lazygit procs rg shfmt starship tssh yazi yq zoxide
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
