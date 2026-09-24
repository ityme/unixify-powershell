# 系统信息与环境变量。

# 用途：以易读容量显示 Windows 文件系统驱动器使用情况。
# 示例：df -h
function global:df {
    Get-PSDrive -PSProvider FileSystem |
        ForEach-Object {
            $total = $_.Used + $_.Free
            [pscustomobject]@{
                Filesystem = $_.Name + ':'
                Size       = if ($total) {
                    '{0:N1} GiB' -f ($total / 1GB)
                } else {
                    '?'
                }
                Used       = if ($null -ne $_.Used) {
                    '{0:N1} GiB' -f ($_.Used / 1GB)
                } else {
                    '?'
                }
                Available  = if ($null -ne $_.Free) {
                    '{0:N1} GiB' -f ($_.Free / 1GB)
                } else {
                    '?'
                }
                UsePercent = if ($total) {
                    '{0:P0}' -f ($_.Used / $total)
                } else {
                    '?'
                }
                MountedOn  = unixpath $_.Root
            }
        }
}

# 用途：显示 Windows 物理内存总量、已用量和可用量。
# 示例：free -h
function global:free {
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $total = [double]$operatingSystem.TotalVisibleMemorySize * 1KB
    $available = [double]$operatingSystem.FreePhysicalMemory * 1KB

    [pscustomobject]@{
        Type      = 'Mem'
        Total     = '{0:N1} GiB' -f ($total / 1GB)
        Used      = '{0:N1} GiB' -f (($total - $available) / 1GB)
        Available = '{0:N1} GiB' -f ($available / 1GB)
    }
}

# 用途：列出当前进程的全部环境变量。
# 示例：env | grep PATH
function global:env {
    Get-ChildItem Env: | Sort-Object Name
}

# 用途：设置当前 PowerShell 进程的环境变量。
# 示例：export APP_ENV=dev
function global:export {
    foreach ($assignment in $args) {
        if ($assignment -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable(
                $Matches[1],
                $Matches[2],
                'Process'
            )
        } else {
            Write-Error "Invalid assignment: $assignment"
        }
    }
}

# 用途：输出 Windows 内核标识；-a 显示主机、版本和架构。
# 示例：uname -a
function global:uname {
    if ($args -notcontains '-a') {
        return 'Windows_NT'
    }

    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        Kernel   = 'Windows_NT'
        Hostname = [Environment]::MachineName
        Release  = $operatingSystem.Version
        Build    = $operatingSystem.BuildNumber
        Machine  = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    }
}

Export-ModuleMember -Function @()
