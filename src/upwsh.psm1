# upwsh 命令入口。实现在 scripts/upwsh.ps1。

function global:upwsh {
    $installer = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot 'scripts\upwsh.ps1')
    )
    & $installer @args
}

Export-ModuleMember -Function @()
