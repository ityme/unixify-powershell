# PowerShell 7 入口：加载顺序和全局 Remove-Alias。

if ($PSVersionTable.PSVersion.Major -lt 7) {
    return
}

function Import-ShellModule {
    param([Parameter(Mandatory)][string]$Name)

    Import-Module (Join-Path $PSScriptRoot $Name) -Global -DisableNameChecking
}

Import-ShellModule 'path.psm1'
Import-ShellModule 'unix.psm1'
Import-ShellModule 'fs.psm1'
Import-ShellModule 'proc.psm1'
Import-ShellModule 'text.psm1'
Import-ShellModule 'sys.psm1'
Import-ShellModule 'tools.psm1'
Import-ShellModule 'upwsh.psm1'
. (Join-Path $PSScriptRoot 'alias.ps1')
Import-ShellModule 'completion.psm1'
Import-ShellModule 'term.psm1'

# AllScope 别名必须在 dot-source 的入口里删除。
Remove-Alias -Name @(
    'cd'
    'w'
    't'
    'i'
    'd'
    'gs'
    'grep'
    'ps'
    'kill'
    'rm'
    'cp'
    'mv'
    'mkdir'
) -Scope Global -Force -ErrorAction Ignore
if (Get-Command ls -CommandType Function -ErrorAction SilentlyContinue) {
    Remove-Alias -Name ls, tree -Scope Global -Force -ErrorAction Ignore
}

Import-ShellModule 'hook.psm1'
