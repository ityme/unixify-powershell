# upwsh 命令入口。实现在 script/upwsh.ps1。

function global:upwsh {
    $installer = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\script\upwsh.ps1')
    )
    & $installer @args
}

Export-ModuleMember -Function @()
