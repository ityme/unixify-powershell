# 从安装树用 pwsh -File 跑 uninstall / update 时，拷到临时目录另起进程再删。

function Get-UpwshHostFile {
    $cli = [Environment]::GetCommandLineArgs()
    for ($index = 0; $index -lt $cli.Count; $index++) {
        $token = [string]$cli[$index]
        if ($token -eq '-File' -or $token -eq '-f') {
            if ($index + 1 -lt $cli.Count) {
                try {
                    return [IO.Path]::GetFullPath([string]$cli[$index + 1])
                } catch {
                    return [string]$cli[$index + 1]
                }
            }
        }
        if ($token -match '^-File:(.+)$') {
            try {
                return [IO.Path]::GetFullPath($Matches[1])
            } catch {
                return $Matches[1]
            }
        }
    }
    return $null
}

function Test-UpwshPathUnder {
    param([string]$Path, [string]$Root)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
        $prefix = $rootFull + '\'
        return $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            ($full.TrimEnd('\', '/') -ieq $rootFull)
    } catch {
        return $false
    }
}

function Copy-UpwshSetupScripts {
    param([string]$Destination)

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($name in @('install.ps1', 'uninstall.ps1', 'update.ps1', '_relaunch.ps1')) {
        $source = Join-Path $PSScriptRoot $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $Destination $name) -Force
        }
    }
}

function Start-UpwshRelaunchIfNeeded {
    param(
        [string]$InstallHome,
        [string]$EntryName,
        [object[]]$Arguments
    )

    if ($env:UPWSH_UNINSTALL_REEXEC) {
        return $false
    }
    if ($env:UPWSH_SKIP_RELAUNCH) {
        return $false
    }
    $hostFile = Get-UpwshHostFile
    if (-not (Test-UpwshPathUnder -Path $hostFile -Root $InstallHome)) {
        return $false
    }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) (
        'upwsh-run-' + [Guid]::NewGuid().ToString('N')
    )
    Copy-UpwshSetupScripts -Destination $tempDir
    $target = Join-Path $tempDir $EntryName
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "missing relaunch script: $target"
    }

    $env:UPWSH_UNINSTALL_REEXEC = '1'
    $env:UPWSH_UNINSTALL_WAIT_PID = "$PID"
    $exe = (Get-Process -Id $PID).Path
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $exe
    $start.UseShellExecute = $false
    $workingDirectory = (Get-Location).ProviderPath
    $start.WorkingDirectory = if (Test-UpwshPathUnder -Path $workingDirectory -Root $InstallHome) {
        $tempDir
    } else {
        $workingDirectory
    }
    foreach ($token in @('-NoLogo', '-NoProfile', '-File', $target) + @($Arguments)) {
        if ($null -ne $token -and [string]$token -ne '') {
            [void]$start.ArgumentList.Add([string]$token)
        }
    }
    [void][Diagnostics.Process]::Start($start)
    Write-Output ("relaunch {0}" -f $target)
    return $true
}

function Wait-UpwshRelaunchParent {
    $raw = $env:UPWSH_UNINSTALL_WAIT_PID
    Remove-Item Env:\UPWSH_UNINSTALL_WAIT_PID -ErrorAction SilentlyContinue
    $processId = 0
    if ([int]::TryParse($raw, [ref]$processId) -and $processId -gt 0 -and $processId -ne $PID) {
        Wait-Process -Id $processId -Timeout 30 -ErrorAction SilentlyContinue
    }
}

function Remove-UpwshTree {
    param([string]$Path, [int]$Tries = 8)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $errorRecord = $null
    for ($index = 0; $index -lt $Tries; $index++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            $errorRecord = $_
            Start-Sleep -Milliseconds ([int][Math]::Min(2000, 50 * [Math]::Pow(2, $index)))
        }
    }
    throw $errorRecord.Exception
}
