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
        $raw = Join-Path $HOME '.config\upwsh'
    } else {
        $raw = ConvertTo-UpwshWindowsPath $raw
    }
    [IO.Path]::GetFullPath($raw)
}

function Get-UpwshBin {
    Join-Path (Get-UpwshHome) 'bin'
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

function Add-UpwshBinToUserPath {
    $bin = Get-UpwshBin
    New-Item -ItemType Directory -Path $bin -Force | Out-Null

    $current = @($env:PATH -split ';' | Where-Object { $_ })
    if (-not ($current | Where-Object { Test-UpwshPathEntry $bin $_ })) {
        $env:PATH = $bin + ';' + $env:PATH
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @()
    if ($userPath) {
        $userEntries = @($userPath -split ';' | Where-Object { $_ })
    }
    if ($env:UPWSH_SKIP_PERSIST_PATH) {
        Write-Output "path    $bin"
        return
    }
    if (-not ($userEntries | Where-Object { Test-UpwshPathEntry $bin $_ })) {
        $updated = @($bin) + $userEntries
        [Environment]::SetEnvironmentVariable(
            'Path',
            ($updated -join ';'),
            'User'
        )
        Write-Output "path    $bin"
    }
}
