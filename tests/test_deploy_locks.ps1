$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}

$runtime = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
$installer = Join-Path $runtime 'script\install.ps1'
$updater = Join-Path $runtime 'script\update.ps1'
$target = Join-Path $HOME '.config\upwsh'
$hook = Join-Path $HOME 'test-profile.ps1'
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()

Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class UpwshDirectoryLockFixture {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(
        string path, uint access, uint share, IntPtr security,
        uint creation, uint flags, IntPtr template);
}
'@
function Hold-Directory {
    param([string]$Path)
    # Read/write sharing, deliberately no FILE_SHARE_DELETE, as with a live directory handle.
    $handle = [UpwshDirectoryLockFixture]::CreateFile($Path, 1, 3, [IntPtr]::Zero, 3, 0x02000000, [IntPtr]::Zero)
    if ($handle.IsInvalid) { throw "cannot create directory lock fixture: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    return $handle
}
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Test-DeployLock {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++ } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Install-Source {
    param([string]$Source, [string]$Entry = $installer)
    Invoke-UpwshTestProcess -UserHome $HOME -File $Entry -Arguments @('--source', $Source)
}

$initial = Install-Source $runtime
Assert-True ($initial.Code -eq 0) $initial.Text
$source = Join-Path $HOME 'source'
[void][IO.Directory]::CreateDirectory($source)
Get-ChildItem -LiteralPath $runtime -Force | Where-Object Name -NE 'tests' |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $source -Recurse -Force }
[IO.File]::AppendAllText((Join-Path $source 'lib\path.psm1'), "`n# updated fixture`n")
$settings = Join-Path $target 'user-settings.ps1'
$tool = Join-Path $target 'tool\bin\fixture.exe'
[IO.File]::WriteAllText($settings, '# personal settings')
[IO.File]::WriteAllText($tool, 'running-tool-fixture')

Test-DeployLock 'a held root directory prevents a whole-tree rename' {
    $handle = Hold-Directory $target
    try {
        $denied = $false
        try { [IO.Directory]::Move($target, "$target-renamed") } catch { $denied = $true }
        if (-not $denied) { [IO.Directory]::Move("$target-renamed", $target) }
        Assert-True $denied 'the fixture did not reproduce the Windows rename restriction'
        Assert-True ([IO.File]::Exists((Join-Path $target 'profile.ps1'))) 'fixture changed runtime'
    } finally { $handle.Dispose() }
}

Test-DeployLock 'install and update work while the root and runtime subdirectories are held open' {
    $handles = @($target, (Join-Path $target 'script'), (Join-Path $target 'theme'), (Join-Path $target 'tool'), (Join-Path $target 'bin')) |
        ForEach-Object { Hold-Directory $_ }
    $fileHandles = @($tool, $settings, (Join-Path $target 'bin\upwsh.cmd')) |
        ForEach-Object { [IO.File]::Open($_, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read) }
    try {
        [IO.File]::WriteAllText((Join-Path $target 'obsolete.ps1'), '# obsolete')
        foreach ($entry in @($installer, $updater)) {
            $result = Install-Source -Source $source -Entry $entry
            Assert-True ($result.Code -eq 0) $result.Text
            Assert-True ([IO.File]::ReadAllText((Join-Path $target 'lib\path.psm1')).Contains('# updated fixture')) 'program file not updated'
            Assert-Equal ([IO.File]::ReadAllText($settings)) '# personal settings'
            Assert-Equal ([IO.File]::ReadAllText($tool)) 'running-tool-fixture'
            Assert-True (-not [IO.File]::Exists((Join-Path $target 'obsolete.ps1'))) 'obsolete program file remained'
        }
    } finally {
        foreach ($handle in $fileHandles) { $handle.Dispose() }
        foreach ($handle in $handles) { $handle.Dispose() }
    }
}

Test-DeployLock 'locked program file fails safely and identifies the file' {
    $locked = Join-Path $target 'lib\path.psm1'
    $beforeProgram = [IO.File]::ReadAllText($locked)
    $beforeAlias = [IO.File]::ReadAllText((Join-Path $target 'lib\alias.ps1'))
    [IO.File]::AppendAllText((Join-Path $source 'lib\alias.ps1'), "`n# change before locked file`n")
    [IO.File]::AppendAllText((Join-Path $source 'lib\path.psm1'), "`n# change locked file`n")
    $rootHandle = Hold-Directory $target
    $fileHandle = [IO.File]::Open($locked, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $result = Install-Source $source
        Assert-Equal $result.Code 1
        Assert-True ($result.Text.Contains('path.psm1')) $result.Text
        Assert-Equal ([IO.File]::ReadAllText($locked)) $beforeProgram
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $target 'lib\alias.ps1'))) $beforeAlias
        Assert-Equal ([IO.File]::ReadAllText($settings)) '# personal settings'
        Assert-Equal ([IO.File]::ReadAllText($tool)) 'running-tool-fixture'
    } finally { $fileHandle.Dispose(); $rootHandle.Dispose() }
}

Test-DeployLock 'configuration failure restores files while the root directory stays locked' {
    $before = [IO.File]::ReadAllText((Join-Path $target 'lib\alias.ps1'))
    $beforeHome = [IO.File]::ReadAllText((Join-Path $target 'lib\upwsh_home.ps1'))
    $obsolete = Join-Path $target 'obsolete-on-failed-update.ps1'
    [IO.File]::WriteAllText($obsolete, '# restore obsolete on failure')
    [IO.File]::WriteAllText((Join-Path $source 'extra-default.ps1'), '# new template')
    [IO.File]::WriteAllText((Join-Path $source 'lib\upwsh_home.ps1'), "throw 'fixture configuration failure'`n")
    $handle = Hold-Directory $target
    try {
        $result = Install-Source $source
        Assert-Equal $result.Code 1
        Assert-True ($result.Text.Contains('fixture configuration failure')) $result.Text
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $target 'lib\alias.ps1'))) $before
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $target 'lib\upwsh_home.ps1'))) $beforeHome
        Assert-Equal ([IO.File]::ReadAllText($settings)) '# personal settings'
        Assert-Equal ([IO.File]::ReadAllText($tool)) 'running-tool-fixture'
        Assert-Equal ([IO.File]::ReadAllText($obsolete)) '# restore obsolete on failure'
        Assert-True (-not [IO.File]::Exists((Join-Path $target 'extra-default.ps1'))) 'failed deployment left a new template'
        Assert-True ((@(Get-ChildItem -LiteralPath (Split-Path $target) -Directory -Filter '.upwsh-*')).Count -eq 0) $result.Text
    } finally { $handle.Dispose() }
}

Test-DeployLock 'failed first installation removes new files' {
    $freshUser = Join-Path $HOME 'fresh-user'
    [void][IO.Directory]::CreateDirectory($freshUser)
    $result = Invoke-UpwshTestProcess -UserHome $freshUser -File $installer -Arguments @('--source', $source)
    Assert-Equal $result.Code 1
    Assert-True ($result.Text.Contains('fixture configuration failure')) $result.Text
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $freshUser '.config\upwsh'))) 'failed first install left a partial runtime'
}

if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) deployment lock tests failed."
}
Write-Output "$script:Passed deployment lock tests passed."
