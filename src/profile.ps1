# PowerShell 7 入口：加载顺序和全局 Remove-Alias。

if ($PSVersionTable.PSVersion.Major -lt 7) {
    return
}

function Import-ShellModule {
    param([Parameter(Mandatory)][string]$Name)

    Import-Module (Join-Path $PSScriptRoot $Name) -Global -DisableNameChecking
}

. (Join-Path $PSScriptRoot 'upwsh_home.ps1')
$script:UpwshBin = Get-UpwshBin
New-Item -ItemType Directory -Path $script:UpwshBin -Force | Out-Null
if (
    -not (
        @($env:PATH -split ';') |
            Where-Object {
                $_ -and (Test-UpwshPathEntry $script:UpwshBin $_)
            }
    )
) {
    $env:PATH = $script:UpwshBin + ';' + $env:PATH
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

$script:CustomRoot = Join-Path $PSScriptRoot 'custom'
if (Test-Path -LiteralPath $script:CustomRoot -PathType Container) {
    Get-ChildItem -LiteralPath $script:CustomRoot -Filter '*.ps1' -File |
        Sort-Object Name |
        ForEach-Object {
            . $_.FullName
        }
}

Import-ShellModule 'hook.psm1'
