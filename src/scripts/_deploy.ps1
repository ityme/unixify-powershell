# Shared deployment for install/update. Source acquisition happens before this file is loaded.
function Test-UpwshRuntime {
    param([string]$Root)

    foreach ($name in @(
        'profile.ps1', 'path_convert.ps1', 'upwsh_home.ps1', 'alias.ps1',
        'path.psm1', 'unix.psm1', 'fs.psm1', 'proc.psm1', 'text.psm1', 'sys.psm1',
        'tools.psm1', 'upwsh.psm1', 'completion.psm1', 'git_completion.psm1', 'term.psm1', 'hook.psm1',
        'scripts\install.ps1', 'scripts\update.ps1', 'scripts\uninstall.ps1',
        'scripts\upwsh.ps1', 'scripts\install_profile.ps1', 'scripts\install_cli_tools.ps1',
        'scripts\_deploy.ps1', 'scripts\_relaunch.ps1'
    )) {
        if (-not [IO.File]::Exists([IO.Path]::Combine($Root, $name))) {
            throw "invalid runtime: missing $name"
        }
    }
    $scripts = foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.Name -in @('tests', 'custom', 'tool', 'bin', '.git')) { continue }
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File | Where-Object Extension -In '.ps1', '.psm1'
        } elseif ($item.Extension -in @('.ps1', '.psm1')) { $item }
    }
    foreach ($file in $scripts) {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "invalid runtime: $($file.Name): $($errors[0].Message)" }
    }
}

function Copy-UpwshRuntime {
    param([string]$Source, [string]$Destination)

    [void][IO.Directory]::CreateDirectory($Destination)
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @('tests', 'custom', 'tool', 'bin', '.git')) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Recurse -Force
    }
}

function Copy-UpwshCustomDefaults {
    param([string]$Source, [string]$Destination)

    [void][IO.Directory]::CreateDirectory($Destination)
    if (-not [IO.Directory]::Exists($Source)) { return }
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $target = Join-Path $Destination $item.Name
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
        }
    }
}

function Get-UpwshEnvironmentSnapshot {
    $values = @{}
    if (-not $env:UPWSH_SKIP_PERSIST_PATH) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
        try {
            foreach ($name in @('UPWSH_HOME', 'Path')) {
                $exists = $key -and $name -in $key.GetValueNames()
                $values[$name] = [pscustomobject]@{
                    Exists = [bool]$exists
                    Value = if ($exists) { $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
                    Kind = if ($exists) { $key.GetValueKind($name) } else { $null }
                }
            }
        } finally { if ($key) { $key.Close() } }
    }
    [pscustomobject]@{ Home = $env:UPWSH_HOME; Path = $env:PATH; UserValues = $values }
}

function Restore-UpwshEnvironment {
    param($Snapshot)

    $env:UPWSH_HOME = $Snapshot.Home
    $env:PATH = $Snapshot.Path
    if ($Snapshot.UserValues.Count) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
        try {
            foreach ($name in $Snapshot.UserValues.Keys) {
                $value = $Snapshot.UserValues[$name]
                if ($value.Exists) { $key.SetValue($name, $value.Value, $value.Kind) }
                else { $key.DeleteValue($name, $false) }
            }
        } finally { $key.Close() }
    }
}

function Install-UpwshRuntime {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$ProfilePath,
        [bool]$Enable
    )

    $sourcePath = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/')
    $targetPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
    if ($sourcePath -ieq $targetPath -or $sourcePath.StartsWith($targetPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'the installed runtime cannot be its own source; use a local project or a download'
    }
    if (Test-Path -LiteralPath (Join-Path $targetPath '.git')) { throw 'refusing to replace a git checkout' }
    if (Test-Path -LiteralPath $ProfilePath -PathType Container) { throw "profile path is a directory: $ProfilePath" }
    Test-UpwshRuntime $sourcePath

    $parent = Split-Path -Parent $targetPath
    [void][IO.Directory]::CreateDirectory($parent)
    $id = [guid]::NewGuid().ToString('N')
    $stage = Join-Path $parent ".upwsh-stage-$id"
    $backup = Join-Path $parent ".upwsh-backup-$id"
    $hadTarget = Test-Path -LiteralPath $targetPath
    $hadProfile = [IO.File]::Exists($ProfilePath)
    $profileBytes = if ($hadProfile) { [IO.File]::ReadAllBytes($ProfilePath) } else { $null }
    $environment = Get-UpwshEnvironmentSnapshot
    $savedTree = $false
    $newTree = $false
    $configurationStarted = $false
    $committed = $false
    $rollbackFailed = $false
    $preserved = [Collections.Generic.List[string]]::new()
    $output = [Collections.Generic.List[object]]::new()
    try {
        Copy-UpwshRuntime -Source $sourcePath -Destination $stage
        Test-UpwshRuntime $stage
        # Keep the original custom untouched in the backup; stage a copy and fill missing samples.
        $custom = Join-Path $targetPath 'custom'
        if (Test-Path -LiteralPath $custom) {
            Copy-Item -LiteralPath $custom -Destination (Join-Path $stage 'custom') -Recurse -Force
        }
        Copy-UpwshCustomDefaults -Source (Join-Path $sourcePath 'custom') -Destination (Join-Path $stage 'custom')
        if ($hadTarget) {
            [IO.Directory]::Move($targetPath, $backup)
            $savedTree = $true
        }
        foreach ($name in @('tool', 'bin')) {
            $saved = Join-Path $backup $name
            if ($savedTree -and [IO.Directory]::Exists($saved)) {
                [IO.Directory]::Move($saved, (Join-Path $stage $name))
                $preserved.Add($name)
            }
        }
        # Preserve bin without modifying its original shim; rollback needs its original bytes.
        $shim = Join-Path $stage 'bin\upwsh.cmd'
        $shimBytes = if ([IO.File]::Exists($shim)) { [IO.File]::ReadAllBytes($shim) } else { $null }
        [IO.Directory]::Move($stage, $targetPath)
        $newTree = $true
        $configurationStarted = $true
        . (Join-Path $targetPath 'upwsh_home.ps1')
        foreach ($line in @(Add-UpwshUserEnvironment)) { $output.Add($line) }
        # Disabled installations keep their profile bytes unchanged.
        if ($Enable) {
            foreach ($line in @(& (Join-Path $targetPath 'scripts\install_profile.ps1') -ProfilePath $ProfilePath)) { $output.Add($line) }
        }
        $committed = $true
    } catch {
        $failure = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        if ($configurationStarted) {
            try {
                $shim = Join-Path $targetPath 'bin\upwsh.cmd'
                if ($null -ne $shimBytes) { [IO.File]::WriteAllBytes($shim, $shimBytes) }
                elseif ([IO.File]::Exists($shim)) { [IO.File]::Delete($shim) }
            } catch { $rollbackErrors.Add("shim: $($_.Exception.Message)") }
        }
        try {
            $preservedRoot = if ($newTree) { $targetPath } else { $stage }
            foreach ($name in $preserved) {
                [IO.Directory]::Move((Join-Path $preservedRoot $name), (Join-Path $backup $name))
            }
            if ($newTree) { Remove-Item -LiteralPath $targetPath -Recurse -Force }
            if ($savedTree) { [IO.Directory]::Move($backup, $targetPath) }
        } catch { $rollbackErrors.Add("files: $($_.Exception.Message)") }
        if ($configurationStarted) {
            try {
                if ($hadProfile) { [IO.File]::WriteAllBytes($ProfilePath, $profileBytes) }
                elseif ([IO.File]::Exists($ProfilePath)) { [IO.File]::Delete($ProfilePath) }
            } catch {
                $rollbackErrors.Add("profile: $($_.Exception.Message)")
                if ($hadProfile) {
                    try {
                        [IO.File]::WriteAllBytes("$backup.profile.ps1", $profileBytes)
                        $rollbackErrors.Add("original profile saved at $backup.profile.ps1")
                    } catch { $rollbackErrors.Add("profile backup: $($_.Exception.Message)") }
                }
            }
            try { Restore-UpwshEnvironment $environment }
            catch { $rollbackErrors.Add("environment: $($_.Exception.Message)") }
        }
        if ($rollbackErrors.Count) {
            $rollbackFailed = $true
            throw "deployment failed: $($failure.Exception.Message); rollback incomplete: $($rollbackErrors -join '; '). Recovery locations: $targetPath, $backup and $stage"
        }
        throw $failure
    } finally {
        # A backup is only disposable after commit; keep recovery files if rollback failed.
        if ($committed -and (Test-Path -LiteralPath $backup)) {
            try { Remove-Item -LiteralPath $backup -Recurse -Force }
            catch { Write-Warning "installed successfully; old backup remains at $backup" }
        }
        if (-not $rollbackFailed -and -not (Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $stage)) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Output "home     $targetPath"
    Write-Output "source   $sourcePath"
    Write-Output 'state    deployed'
    $output
    Write-Output ('enabled  ' + $Enable.ToString().ToLowerInvariant())
    Write-Output 'Open a new pwsh to use the installed version.'
}
