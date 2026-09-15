$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot '..\scripts\install_profile.ps1'
$sourceProfile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\profile.ps1'))
$root = Join-Path ([IO.Path]::GetTempPath()) (
    'pwsh-install-profile-' + [Guid]::NewGuid().ToString('N')
)
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()

function Invoke-InstallProfileTest {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    try {
        & $Body
        $script:Passed++
    } catch {
        $script:Failures.Add("$Name`n  $($_.Exception.Message)")
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected
    )

    if ([string]$Actual -cne [string]$Expected) {
        throw "expected '$Expected', got '$Actual'"
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Expected
    )

    if ($Text -notlike "*${Expected}*") {
        throw "expected '$Expected' in '$Text'"
    }
}

function Invoke-Installer {
    param(
        [string]$ProfilePath,
        [string]$Destination,
        [switch]$Check,
        [switch]$Uninstall,
        [switch]$Deploy
    )

    $arguments = @{
        ProfilePath = $ProfilePath
    }
    if ($Destination) {
        $arguments.Destination = $Destination
    }
    if ($Check) {
        $arguments.Check = $true
    }
    if ($Uninstall) {
        $arguments.Uninstall = $true
    }
    if ($Deploy) {
        $arguments.Deploy = $true
    }
    & $installer @arguments | Out-String
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $hook = Join-Path $root 'profile.ps1'
    $deployRoot = Join-Path $root 'deploy'

    Invoke-InstallProfileTest 'check on missing profile reports missing' {
        $output = Invoke-Installer -ProfilePath $hook -Check
        Assert-Contains $output 'state    missing'
        Assert-Contains $output $hook
        Assert-Contains $output $sourceProfile
        Assert-True (-not (Test-Path -LiteralPath $hook)) 'check created a profile file'
    }

    Invoke-InstallProfileTest 'install creates a marked hook to this repo' {
        $output = Invoke-Installer -ProfilePath $hook
        $text = [IO.File]::ReadAllText($hook)
        Assert-Contains $output 'state    installed'
        Assert-Contains $text '# >>> unixify-powershell >>>'
        Assert-Contains $text '# <<< unixify-powershell <<<'
        Assert-Contains $text $sourceProfile
        Assert-Contains $text 'Test-Path -LiteralPath'
    }

    Invoke-InstallProfileTest 'install is idempotent' {
        Invoke-Installer -ProfilePath $hook | Out-Null
        Invoke-Installer -ProfilePath $hook | Out-Null
        $text = [IO.File]::ReadAllText($hook)
        $begins = [regex]::Matches($text, '# >>> unixify-powershell >>>').Count
        Assert-Equal $begins 1
    }

    Invoke-InstallProfileTest 'install preserves existing profile text' {
        $customHook = Join-Path $root 'existing.ps1'
        [IO.File]::WriteAllText($customHook, "Write-Output 'keep-me'`r`n")
        Invoke-Installer -ProfilePath $customHook | Out-Null
        $text = [IO.File]::ReadAllText($customHook)
        Assert-Contains $text 'keep-me'
        Assert-Contains $text '# >>> unixify-powershell >>>'
    }

    Invoke-InstallProfileTest 'install replaces an old marked block' {
        [IO.File]::WriteAllText(
            $hook,
            "# >>> unixify-powershell >>>`r`n. 'C:\old\profile.ps1'`r`n# <<< unixify-powershell <<<`r`n"
        )
        Invoke-Installer -ProfilePath $hook | Out-Null
        $text = [IO.File]::ReadAllText($hook)
        Assert-True ($text -notlike '*C:\old\profile.ps1*') "old target remained:`n$text"
        Assert-Contains $text $sourceProfile
        Assert-Equal ([regex]::Matches($text, '# >>> unixify-powershell >>>').Count) 1
    }

    Invoke-InstallProfileTest 'check reports installed target' {
        $output = Invoke-Installer -ProfilePath $hook -Check
        Assert-Contains $output 'state    installed'
        Assert-Contains $output $sourceProfile
    }

    Invoke-InstallProfileTest 'uninstall removes the marked block only' {
        $customHook = Join-Path $root 'uninstall.ps1'
        [IO.File]::WriteAllText($customHook, "Write-Output 'keep-me'`r`n")
        Invoke-Installer -ProfilePath $customHook | Out-Null
        $output = Invoke-Installer -ProfilePath $customHook -Uninstall
        $text = [IO.File]::ReadAllText($customHook)
        Assert-Contains $output 'state    removed'
        Assert-Contains $text 'keep-me'
        Assert-True ($text -notlike '*unixify-powershell*') "marker remained:`n$text"
    }

    Invoke-InstallProfileTest 'uninstall on missing hook is a no-op' {
        $missing = Join-Path $root 'missing.ps1'
        $output = Invoke-Installer -ProfilePath $missing -Uninstall
        Assert-Contains $output 'state    missing'
        Assert-True (-not (Test-Path -LiteralPath $missing)) 'uninstall created a file'
    }

    Invoke-InstallProfileTest 'deploy copies runtime files and skips tests' {
        $output = Invoke-Installer -ProfilePath $hook -Destination $deployRoot -Deploy
        $deployedProfile = Join-Path $deployRoot 'profile.ps1'
        $text = [IO.File]::ReadAllText($hook)
        Assert-Contains $output 'state    deployed'
        Assert-True (Test-Path -LiteralPath $deployedProfile -PathType Leaf) 'deploy missed profile.ps1'
        Assert-True (
            Test-Path -LiteralPath (Join-Path $deployRoot 'scripts\install_profile.ps1')
        ) 'deploy missed install_profile.ps1'
        Assert-True (
            -not (Test-Path -LiteralPath (Join-Path $deployRoot 'tests'))
        ) 'deploy copied tests'
        Assert-Contains $text $deployedProfile
        Assert-True ($text -notlike "*$sourceProfile*") "deploy still hooked the source tree:`n$text"
    }
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) of $($script:Passed + $script:Failures.Count) install profile tests failed."
}

Write-Output "$script:Passed install profile tests passed."
