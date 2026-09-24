# 进程与命令查找。

function global:which {
    param(
        [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)]
        [string[]]$Name
    )

    $missing = $false
    foreach ($item in $Name) {
        $commands = @(Get-Command $item -All -ErrorAction SilentlyContinue)
        if ($commands.Count -eq 0) {
            $missing = $true
            continue
        }

        $commands | Select-Object Name, CommandType, Source
    }
    $global:LASTEXITCODE = if ($missing) { 1 } else { 0 }
}

# 用途：接受常用 ps 参数并返回原生进程对象，保持 PowerShell 的横向表格视图。
# 示例：ps -ef | grep Weixin
function global:ps {
    $arguments = @($args)
    $detailedTokens = @('-e', '-f', '-ef', '-fe', 'aux', 'ax')
    $unknownOptions = @(
        $arguments |
            Where-Object {
                $_ -is [string] -and $_.StartsWith('-') -and $_ -notin $detailedTokens
            }
    )
    if ($unknownOptions.Count -gt 0) {
        $global:LASTEXITCODE = 2
        Write-Error "ps: unsupported option '$($unknownOptions[0])'."
        return
    }

    $useDetailedView = @(
        $arguments |
            Where-Object { $_ -in $detailedTokens }
    ).Count -gt 0

    if (-not $useDetailedView) {
        if ($arguments.Count -eq 0) {
            Get-Process
            $global:LASTEXITCODE = 0
        } else {
            $matches = @(Get-Process -Name $arguments -ErrorAction SilentlyContinue)
            $matches
            $global:LASTEXITCODE = if ($matches.Count -gt 0) { 0 } else { 1 }
        }
        return
    }

    Get-Process -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}

# 用途：按进程名或完整命令行查找 Windows 进程，供 pgrep 和 pkill 复用。
# 示例：Find-MatchingProcess 'pwsh' -FullCommand
function Find-MatchingProcess {
    param(
        [string]$Pattern,
        [switch]$FullCommand
    )

    $matcher = [regex]::new(
        $Pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($FullCommand) {
        Get-CimInstance Win32_Process |
            Where-Object {
                $matcher.IsMatch([string]$_.CommandLine)
            }
        return
    }

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $matcher.IsMatch([string]$_.ProcessName)
        } |
        ForEach-Object {
            [pscustomobject]@{
                ProcessId  = $_.Id
                Name       = $_.ProcessName
                CommandLine = $null
            }
        }
}

# 用途：按名称或命令行查找进程并输出 PID，可用 -a 同时显示命令。
# 示例：pgrep -af codex
function global:pgrep {
    try {
        $parsed = ConvertFrom-UnixArguments -Arguments @($args) -AllowedOptions @('a', 'f')
    } catch {
        $global:LASTEXITCODE = 2
        Write-Error $_
        return
    }

    if ($parsed.Operands.Count -ne 1) {
        $global:LASTEXITCODE = 2
        Write-Error 'Usage: pgrep [-a] [-f] PATTERN'
        return
    }

    try {
        $matches = @(
            Find-MatchingProcess -Pattern $parsed.Operands[0] -FullCommand:$parsed.Options.Contains('f')
        )
    } catch {
        $global:LASTEXITCODE = 2
        Write-Error $_
        return
    }

    $global:LASTEXITCODE = if ($matches.Count -gt 0) { 0 } else { 1 }
    $matches |
        ForEach-Object {
            if ($parsed.Options.Contains('a')) {
                [pscustomobject]@{
                    PID     = $_.ProcessId
                    COMMAND = if ($_.CommandLine) { $_.CommandLine } else { $_.Name }
                }
            } else {
                [int]$_.ProcessId
            }
        }
}

# 用途：按名称或完整命令行查找并终止进程。
# 示例：pkill -f demo-server
function global:pkill {
    try {
        $parsed = ConvertFrom-UnixArguments -Arguments @($args) -AllowedOptions @('f')
    } catch {
        $global:LASTEXITCODE = 2
        Write-Error $_
        return
    }

    if ($parsed.Operands.Count -ne 1) {
        $global:LASTEXITCODE = 2
        Write-Error 'Usage: pkill [-f] PATTERN'
        return
    }

    try {
        $matches = @(
            Find-MatchingProcess -Pattern $parsed.Operands[0] -FullCommand:$parsed.Options.Contains('f') |
                Where-Object ProcessId -ne $PID
        )
        foreach ($match in $matches) {
            Stop-Process -Id $match.ProcessId -Force -ErrorAction Stop
        }
        $global:LASTEXITCODE = if ($matches.Count -gt 0) { 0 } else { 1 }
    } catch {
        $global:LASTEXITCODE = 1
        Write-Error $_
    }
}

# 用途：按 PID 停止进程；接受常用的 -9 写法。
# 示例：kill -9 1234
function global:kill {
    try {
        $parsed = ConvertFrom-UnixArguments -Arguments @($args) -AllowedOptions @('9')
    } catch {
        $global:LASTEXITCODE = 2
        Write-Error $_
        return
    }

    if ($parsed.Operands.Count -eq 0) {
        $global:LASTEXITCODE = 2
        Write-Error 'Usage: kill [-9] PID...'
        return
    }

    try {
        Stop-Process -Id ([int[]]$parsed.Operands) -Force:$parsed.Options.Contains('9') -ErrorAction Stop
        $global:LASTEXITCODE = 0
    } catch {
        $global:LASTEXITCODE = 1
        Write-Error $_
    }
}

Export-ModuleMember -Function @()
