# 外部 CLI 适配。安装入口是 upwsh tool，见 scripts/upwsh.ps1。
# 旧会话可能还留着独立的 tool / tools，加载时清掉。
Remove-Item -Path Function:global:tool, Function:global:tools, Alias:tools -ErrorAction Ignore

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

Export-ModuleMember -Function @()
