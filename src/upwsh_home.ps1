# UPWSH_HOME：项目根。未设置时为 ~/.config/upwsh。
# 命令垫片在 $UPWSH_HOME\bin\upwsh.cmd，CLI 在 $UPWSH_HOME\tool\bin。

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

function Get-UpwshToolBin {
    Join-Path (Get-UpwshHome) 'tool\bin'
}

function Get-UpwshCommandShim {
    Join-Path (Get-UpwshBin) 'upwsh.cmd'
}

function Get-UpwshManagedPathSpecs {
    @(
        [pscustomobject]@{
            Literal = '%UPWSH_HOME%\bin'
            Path    = Get-UpwshBin
        }
        [pscustomobject]@{
            Literal = '%UPWSH_HOME%\tool\bin'
            Path    = Get-UpwshToolBin
        }
    )
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

function Test-UpwshManagedPathEntry {
    param([string]$Entry)

    foreach ($spec in Get-UpwshManagedPathSpecs) {
        if ($Entry -ieq $spec.Literal) {
            return $true
        }
        if (Test-UpwshPathEntry $spec.Path $Entry) {
            return $true
        }
    }
    return $false
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

function Add-UpwshSessionPath {
    foreach ($spec in Get-UpwshManagedPathSpecs) {
        New-Item -ItemType Directory -Path $spec.Path -Force | Out-Null
        $current = @($env:PATH -split ';' | Where-Object { $_ })
        if (-not ($current | Where-Object { Test-UpwshPathEntry $spec.Path $_ })) {
            $env:PATH = $env:PATH.TrimEnd(';') + ';' + $spec.Path
        }
    }
}

function Write-UpwshCommandShim {
    $bin = Get-UpwshBin
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $shim = Get-UpwshCommandShim
    $text = @(
        '@echo off'
        'pwsh -NoLogo -NoProfile -File "%~dp0..\scripts\upwsh.ps1" %*'
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($shim, $text)
    Write-Output "cmd     $shim"
}

function Add-UpwshUserEnvironment {
    $upwshHome = Get-UpwshHome
    $specs = @(Get-UpwshManagedPathSpecs)
    $env:UPWSH_HOME = $upwshHome
    Add-UpwshSessionPath
    Write-UpwshCommandShim

    if ($env:UPWSH_SKIP_PERSIST_PATH) {
        Write-Output "home    $upwshHome"
        foreach ($spec in $specs) {
            Write-Output "path    $($spec.Literal)"
        }
        return
    }

    $userHome = [Environment]::GetEnvironmentVariable('UPWSH_HOME', 'User')
    if ($userHome -ne $upwshHome) {
        [Environment]::SetEnvironmentVariable('UPWSH_HOME', $upwshHome, 'User')
        Write-Output "home    $upwshHome"
    }

    $entries = @(
        Get-UpwshUserPathEntries |
            Where-Object { -not (Test-UpwshManagedPathEntry $_) }
    )
    $updated = (@($entries) + @($specs.Literal)) -join ';'
    $previous = Get-UpwshUserEnvironmentValue 'Path'
    if ("$previous" -ne $updated) {
        Set-UpwshUserPath $updated
        [Environment]::SetEnvironmentVariable('UPWSH_HOME', $upwshHome, 'User')
        foreach ($spec in $specs) {
            Write-Output "path    $($spec.Literal)"
        }
    }
}

function Remove-UpwshUserEnvironment {
    $upwshHome = Get-UpwshHome
    $env:PATH = @(
        $env:PATH -split ';' |
            Where-Object { $_ -and -not (Test-UpwshManagedPathEntry $_) }
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
            Where-Object { -not (Test-UpwshManagedPathEntry $_) }
    )
    $previous = Get-UpwshUserEnvironmentValue 'Path'
    $updated = $entries -join ';'
    if ("$previous" -ne $updated) {
        Set-UpwshUserPath $updated
        Write-Output 'path    removed'
    }
}
