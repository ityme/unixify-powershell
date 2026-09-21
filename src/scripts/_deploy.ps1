# Shared deployment for install/update. Source acquisition happens before this file is loaded.
function Test-UpwshThemeHeaders {
    param([string]$Root, [string[]]$Names)

    foreach ($name in $Names) {
        $file = Join-Path $Root $name
        if (-not [IO.File]::Exists($file)) { continue }
        try {
            if ([IO.FileInfo]::new($file).Length -gt 65536) { throw 'theme exceeds 64 KiB' }
            $data = [IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($data -isnot [Collections.IDictionary] -or
                ($data.Version -isnot [int] -and $data.Version -isnot [long]) -or $data.Version -ne 2 -or
                $data.Modules -isnot [Collections.IDictionary] -or $data.Order -isnot [array]) {
                throw 'requires Version 2 with Order/Modules'
            }
        } catch {
            throw "cannot deploy with theme '$file': $($_.Exception.Message). Back up old themes outside themes/, replace them with v2 files or move them out, then retry. No theme conversion or overwrite is performed."
        }
    }
}

function Get-UpwshThemeNames {
    param([string]$Root)
    if (-not [IO.Directory]::Exists((Join-Path $Root 'themes'))) { return @() }
    return @(Get-ChildItem -LiteralPath (Join-Path $Root 'themes') -Filter '*.json' -File | ForEach-Object BaseName)
}

function Move-UpwshLegacyThemes {
    param([string]$Target, [string[]]$BundledNames, [string]$Backup, $Migrations, $Created)

    $legacyRoot = Join-Path $Target 'themes'
    if (-not [IO.Directory]::Exists($legacyRoot)) { return }
    $customRoot = Join-Path $Target 'custom\themes'
    foreach ($file in Get-ChildItem -LiteralPath $legacyRoot -Filter '*.json' -File) {
        if ($file.BaseName -in $BundledNames) { continue }
        $destination = Join-Path $customRoot $file.Name
        if ([IO.File]::Exists($destination)) {
            Write-Warning "keeping existing custom theme; legacy file remains in themes: $($file.Name)"
            continue
        }
        New-UpwshDeploymentDirectory -Path $customRoot -Created $Created
        [IO.File]::Move($file.FullName, $destination)
        $Migrations.Add([pscustomobject]@{ Legacy = $file.FullName; Destination = $destination })
    }
}

function Test-UpwshRuntime {
    param([string]$Root)

    foreach ($name in @(
        'profile.ps1', 'path_convert.ps1', 'upwsh_home.ps1', 'alias.ps1',
        'path.psm1', 'unix.psm1', 'fs.psm1', 'proc.psm1', 'text.psm1', 'sys.psm1',
        'tools.psm1', 'upwsh.psm1', 'completion.psm1', 'git_completion.psm1', 'theme.psm1', 'themes\pure-default.json', 'prompt.psm1', 'term.psm1', 'hook.psm1',
        'scripts\install.ps1', 'scripts\update.ps1', 'scripts\uninstall.ps1',
        'scripts\upwsh.ps1', 'scripts\install_profile.ps1', 'scripts\install_cli_tools.ps1',
        'scripts\_deploy.ps1', 'scripts\_relaunch.ps1'
    )) {
        if (-not [IO.File]::Exists([IO.Path]::Combine($Root, $name))) {
            throw "invalid runtime: missing $name"
        }
    }
    Test-UpwshThemeHeaders -Root (Join-Path $Root 'themes') -Names @(Get-ChildItem -LiteralPath (Join-Path $Root 'themes') -Filter '*.json' -File | ForEach-Object Name)
    $scripts = foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.Name -in @('tests', 'custom', 'themes', 'tool', 'bin', '.git')) { continue }
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

function Get-UpwshManagedFiles {
    param([string]$Root)

    if (-not [IO.Directory]::Exists($Root)) { return }
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.Name -in @('custom', 'themes', 'tool', 'bin', '.git')) { continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "refusing to replace a linked runtime path: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Recurse -Force) {
                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "refusing to replace a linked runtime path: $($child.FullName)"
                }
                if (-not $child.PSIsContainer) { $child }
            }
        } else { $item }
    }
}

function New-UpwshDeploymentDirectory {
    param([string]$Path, [Collections.Generic.List[string]]$Created)

    if ([IO.Directory]::Exists($Path)) { return }
    $parent = [IO.Path]::GetDirectoryName($Path)
    if ($parent) { New-UpwshDeploymentDirectory -Path $parent -Created $Created }
    [void][IO.Directory]::CreateDirectory($Path)
    $Created.Add($Path)
}

function Set-UpwshDeploymentFile {
    param([string]$Source, [string]$Target, [string]$Backup, $Journal, $Created)

    New-UpwshDeploymentDirectory -Path ([IO.Path]::GetDirectoryName($Target)) -Created $Created
    if ([IO.File]::Exists($Target)) {
        $old = [IO.File]::ReadAllBytes($Target)
        $new = [IO.File]::ReadAllBytes($Source)
        if ($old.Length -eq $new.Length -and [Convert]::ToBase64String($old) -ceq [Convert]::ToBase64String($new)) { return }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Backup))
        [IO.File]::Replace($Source, $Target, $Backup)
        $Journal.Add([pscustomobject]@{ Target = $Target; Backup = $Backup; Added = $false })
    } else {
        [IO.File]::Move($Source, $Target)
        $Journal.Add([pscustomobject]@{ Target = $Target; Backup = $null; Added = $true })
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
    $hadProfile = [IO.File]::Exists($ProfilePath)
    $profileBytes = if ($hadProfile) { [IO.File]::ReadAllBytes($ProfilePath) } else { $null }
    $environment = Get-UpwshEnvironmentSnapshot
    $configurationStarted = $false
    $rollbackFailed = $false
    $journal = [Collections.Generic.List[object]]::new()
    $migrations = [Collections.Generic.List[object]]::new()
    $created = [Collections.Generic.List[string]]::new()
    $activeFile = $null
    $shim = Join-Path $targetPath 'bin\upwsh.cmd'
    $shimBytes = if ([IO.File]::Exists($shim)) { [IO.File]::ReadAllBytes($shim) } else { $null }
    $output = [Collections.Generic.List[object]]::new()
    try {
        Copy-UpwshRuntime -Source $sourcePath -Destination $stage
        Test-UpwshRuntime $stage
        Move-UpwshLegacyThemes -Target $targetPath -BundledNames (Get-UpwshThemeNames $sourcePath) -Backup $backup -Migrations $migrations -Created $created
        # Windows can hold directory handles for running shells/tools. Keep all live directories
        # in place and replace only managed files, recording enough to undo every successful edit.
        $oldFiles = @(Get-UpwshManagedFiles $targetPath)
        $newFiles = @(Get-UpwshManagedFiles $stage)
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $newFiles) {
            $relative = [IO.Path]::GetRelativePath($stage, $file.FullName)
            [void]$names.Add($relative)
            $activeFile = Join-Path $targetPath $relative
            Set-UpwshDeploymentFile -Source $file.FullName -Target $activeFile -Backup (Join-Path $backup $relative) -Journal $journal -Created $created
        }
        foreach ($file in $oldFiles) {
            $relative = [IO.Path]::GetRelativePath($targetPath, $file.FullName)
            if ($names.Contains($relative)) { continue }
            $activeFile = $file.FullName
            $saved = Join-Path $backup $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved))
            [IO.File]::Move($activeFile, $saved)
            $journal.Add([pscustomobject]@{ Target = $activeFile; Backup = $saved; Added = $false })
        }
        foreach ($theme in Get-ChildItem -LiteralPath (Join-Path $stage 'themes') -Filter '*.json' -File) {
            $activeFile = Join-Path $targetPath ('themes\' + $theme.Name)
            Set-UpwshDeploymentFile -Source $theme.FullName -Target $activeFile -Backup (Join-Path $backup ('themes\' + $theme.Name)) -Journal $journal -Created $created
        }
        foreach ($folder in @('custom', 'custom\themes', 'bin', 'tool\bin')) {
            $defaults = Join-Path $stage $folder
            if ($folder -eq 'custom') {
                Copy-UpwshCustomDefaults -Source (Join-Path $sourcePath $folder) -Destination $defaults
            }
            if (-not [IO.Directory]::Exists($defaults)) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $defaults -Recurse -File -Force) {
                $relative = [IO.Path]::GetRelativePath($stage, $file.FullName)
                $activeFile = Join-Path $targetPath $relative
                if (Test-Path -LiteralPath $activeFile) { continue }
                Set-UpwshDeploymentFile -Source $file.FullName -Target $activeFile -Backup (Join-Path $backup $relative) -Journal $journal -Created $created
            }
        }
        foreach ($name in @('custom', 'custom\themes', 'bin', 'tool\bin')) {
            New-UpwshDeploymentDirectory -Path (Join-Path $targetPath $name) -Created $created
        }
        $activeFile = $null
        $configurationStarted = $true
        . (Join-Path $targetPath 'upwsh_home.ps1')
        foreach ($line in @(Add-UpwshUserEnvironment)) { $output.Add($line) }
        # Disabled installations keep their profile bytes unchanged.
        if ($Enable) {
            foreach ($line in @(& (Join-Path $targetPath 'scripts\install_profile.ps1') -ProfilePath $ProfilePath)) { $output.Add($line) }
        }
    } catch {
        $failure = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        if ($configurationStarted) {
            try {
                $shim = Join-Path $targetPath 'bin\upwsh.cmd'
                if ($null -ne $shimBytes) {
                    if (-not [IO.File]::Exists($shim) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($shim)) -cne [Convert]::ToBase64String($shimBytes)) {
                        [IO.File]::WriteAllBytes($shim, $shimBytes)
                    }
                }
                elseif ([IO.File]::Exists($shim)) { [IO.File]::Delete($shim) }
            } catch { $rollbackErrors.Add("shim: $($_.Exception.Message)") }
        }
        foreach ($migration in $migrations) {
            try {
                if ([IO.File]::Exists($migration.Destination)) { [IO.File]::Move($migration.Destination, $migration.Legacy) }
            } catch { $rollbackErrors.Add("theme migration $($migration.Legacy): $($_.Exception.Message)") }
        }
        for ($index = $journal.Count - 1; $index -ge 0; $index--) {
            $entry = $journal[$index]
            try {
                if ($entry.Added) { [IO.File]::Delete($entry.Target) }
                elseif ([IO.File]::Exists($entry.Target)) { [IO.File]::Replace($entry.Backup, $entry.Target, [Management.Automation.Language.NullString]::Value) }
                else { [IO.File]::Move($entry.Backup, $entry.Target) }
            } catch { $rollbackErrors.Add("$($entry.Target): $($_.Exception.Message)") }
        }
        for ($index = $created.Count - 1; $index -ge 0; $index--) {
            try { [IO.Directory]::Delete($created[$index], $false) }
            catch { $rollbackErrors.Add("$($created[$index]): $($_.Exception.Message)") }
        }
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
        if ($activeFile) {
            throw "could not update '$activeFile': $($failure.Exception.Message). Previous files restored. Close programs using this file, check its permissions, then retry."
        }
        throw $failure
    } finally {
        # Only our private staging/backup directories are removed; never the live install root.
        if (-not $rollbackFailed) {
            foreach ($temporary in @($stage, $backup)) {
                if (Test-Path -LiteralPath $temporary) {
                    try { Remove-Item -LiteralPath $temporary -Recurse -Force }
                    catch { Write-Warning "cleanup incomplete; recovery files remain at $temporary" }
                }
            }
        }
    }
    Write-Output "home     $targetPath"
    Write-Output "source   $sourcePath"
    Write-Output 'state    deployed'
    $output
    Write-Output ('enabled  ' + $Enable.ToString().ToLowerInvariant())
    Write-Output 'Open a new pwsh to use the installed version.'
}
