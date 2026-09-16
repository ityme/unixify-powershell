# UPWSH_HOME：项目根。未设置时为 ~/.config/upwsh。CLI 在 $UPWSH_HOME\bin。

function ConvertTo-UpwshWindowsPath {
    param([string]$Path)

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

function Get-UpwshHome {
    $raw = $env:UPWSH_HOME
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [Environment]::GetEnvironmentVariable('UPWSH_HOME', 'User')
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = Join-Path $HOME '.config\upwsh'
    } else {
        $raw = ConvertTo-UpwshWindowsPath $raw
    }
    [IO.Path]::GetFullPath($raw)
}

function Get-UpwshBin {
    Join-Path (Get-UpwshHome) 'bin'
}

function Get-UpwshBinPathLiteral {
    '%UPWSH_HOME%\bin'
}

function Test-UpwshPathEntry {
    param([string]$Path, [string]$Entry)

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $false
    }
    try {
        return [IO.Path]::GetFullPath($Entry) -eq $Path
    } catch {
        return $false
    }
}

function Get-UpwshUserEnvironmentValue {
    param([string]$Name)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $key) {
        return $null
    }
    try {
        $key.GetValue(
            $Name,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
    } finally {
        $key.Close()
    }
}

function Set-UpwshUserPath {
    param([string]$Value)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) {
        throw 'missing HKCU\Environment'
    }
    try {
        $key.SetValue(
            'Path',
            $Value,
            [Microsoft.Win32.RegistryValueKind]::ExpandString
        )
    } finally {
        $key.Close()
    }
}

function Remove-UpwshUserEnvironmentValue {
    param([string]$Name)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) {
        return $false
    }
    try {
        if ($null -eq $key.GetValue($Name)) {
            return $false
        }
        $key.DeleteValue($Name, $false)
        return $true
    } finally {
        $key.Close()
    }
}

function Get-UpwshUserPathEntries {
    $raw = Get-UpwshUserEnvironmentValue 'Path'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }
    @(
        $raw -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Test-UpwshUserPathHasBin {
    param([string]$Bin)

    $literal = Get-UpwshBinPathLiteral
    foreach ($entry in Get-UpwshUserPathEntries) {
        if ($entry -ieq $literal) {
            return $true
        }
        if (Test-UpwshPathEntry $Bin $entry) {
            return $true
        }
    }
    return $false
}

function Add-UpwshUserEnvironment {
    $upwshHome = Get-UpwshHome
    $bin = Get-UpwshBin
    $literal = Get-UpwshBinPathLiteral
    New-Item -ItemType Directory -Path $bin -Force | Out-Null

    $env:UPWSH_HOME = $upwshHome
    $current = @($env:PATH -split ';' | Where-Object { $_ })
    if (-not ($current | Where-Object { Test-UpwshPathEntry $bin $_ })) {
        $env:PATH = $bin + ';' + $env:PATH
    }

    if ($env:UPWSH_SKIP_PERSIST_PATH) {
        Write-Output "home    $upwshHome"
        Write-Output "path    $literal"
        return
    }

    $userHome = [Environment]::GetEnvironmentVariable('UPWSH_HOME', 'User')
    if ($userHome -ne $upwshHome) {
        [Environment]::SetEnvironmentVariable('UPWSH_HOME', $upwshHome, 'User')
        Write-Output "home    $upwshHome"
    }

    if (-not (Test-UpwshUserPathHasBin $bin)) {
        $updated = @($literal) + @(Get-UpwshUserPathEntries)
        Set-UpwshUserPath ($updated -join ';')
        [Environment]::SetEnvironmentVariable('UPWSH_HOME', $upwshHome, 'User')
        Write-Output "path    $literal"
    }
}

function Remove-UpwshUserEnvironment {
    $upwshHome = Get-UpwshHome
    $bin = Get-UpwshBin
    $literal = Get-UpwshBinPathLiteral

    $env:PATH = @(
        $env:PATH -split ';' |
            Where-Object { $_ -and -not (Test-UpwshPathEntry $bin $_) }
    ) -join ';'
    if (-not [string]::IsNullOrWhiteSpace($env:UPWSH_HOME)) {
        try {
            if ([IO.Path]::GetFullPath((ConvertTo-UpwshWindowsPath $env:UPWSH_HOME)) -eq $upwshHome) {
                Remove-Item Env:\UPWSH_HOME -ErrorAction SilentlyContinue
            }
        } catch {
            Remove-Item Env:\UPWSH_HOME -ErrorAction SilentlyContinue
        }
    }

    if ($env:UPWSH_SKIP_PERSIST_PATH) {
        Write-Output 'home    removed'
        Write-Output 'path    removed'
        return
    }

    if ($null -ne (Get-UpwshUserEnvironmentValue 'UPWSH_HOME')) {
        if (Remove-UpwshUserEnvironmentValue 'UPWSH_HOME') {
            Write-Output 'home    removed'
        }
    }

    $entries = @(
        Get-UpwshUserPathEntries |
            Where-Object { $_ -ine $literal -and -not (Test-UpwshPathEntry $bin $_) }
    )
    $previous = Get-UpwshUserEnvironmentValue 'Path'
    $updated = $entries -join ';'
    if ("$previous" -ne $updated) {
        Set-UpwshUserPath $updated
        Write-Output 'path    removed'
    }
}
