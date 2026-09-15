$ErrorActionPreference = 'Stop'

$bootstrap = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\bootstrap.ps1'))
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runtimeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root = Join-Path ([IO.Path]::GetTempPath()) (
    'unixify-install-' + [Guid]::NewGuid().ToString('N')
)
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()

function Invoke-InstallTest {
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

function Invoke-Bootstrap {
    param([string[]]$Tokens = @())

    $previous = $global:LASTEXITCODE
    $savedRepo = $env:UNIXIFY_REPO
    $savedRef = $env:UNIXIFY_REF
    $savedDir = $env:UNIXIFY_DIR
    $savedSource = $env:UNIXIFY_SOURCE
    try {
        $env:UNIXIFY_REPO = $null
        $env:UNIXIFY_REF = $null
        $env:UNIXIFY_DIR = $null
        $env:UNIXIFY_SOURCE = $null
        $global:LASTEXITCODE = 0
        $output = & $bootstrap @Tokens 2>&1 | Out-String
        [pscustomobject]@{
            Text = $output
            Code = $global:LASTEXITCODE
        }
    } finally {
        $global:LASTEXITCODE = $previous
        $env:UNIXIFY_REPO = $savedRepo
        $env:UNIXIFY_REF = $savedRef
        $env:UNIXIFY_DIR = $savedDir
        $env:UNIXIFY_SOURCE = $savedSource
    }
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $hook = Join-Path $root 'profile.ps1'
    $deployRoot = Join-Path $root 'deploy'

    Invoke-InstallTest 'no args from this repo deploys sibling runtime' {
        $result = Invoke-Bootstrap -Tokens @(
            '--directory', $deployRoot
            '--profile', $hook
        )
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    deployed'
        Assert-Contains $result.Text $runtimeRoot
        Assert-True (Test-Path -LiteralPath (Join-Path $deployRoot 'profile.ps1') -PathType Leaf) (
            'install missed profile.ps1'
        )
        Assert-True (
            -not (Test-Path -LiteralPath (Join-Path $deployRoot 'tests'))
        ) 'install copied tests'
        $text = [IO.File]::ReadAllText($hook)
        Assert-Contains $text '# >>> unixify-powershell >>>'
        Assert-Contains $text (Join-Path $deployRoot 'profile.ps1')
    }

    Invoke-InstallTest 'help flag prints usage' {
        $result = Invoke-Bootstrap -Tokens @('--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'unixify-powershell'
        Assert-Contains $result.Text '--directory'
        Assert-Contains $result.Text '--source'
        Assert-Contains $result.Text 'curl'
    }

    Invoke-InstallTest 'unknown option prints usage and exits 2' {
        $result = Invoke-Bootstrap -Tokens @('--nope')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option'
        Assert-Contains $result.Text '--directory'
    }

    Invoke-InstallTest 'missing directory prints usage' {
        $result = Invoke-Bootstrap -Tokens @('--directory')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'missing directory'
    }

    Invoke-InstallTest 'source deploys from a local checkout' {
        $customHook = Join-Path $root 'source-profile.ps1'
        $customDir = Join-Path $root 'from-source'
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $sourceRoot
            '--directory', $customDir
            '--profile', $customHook
        )
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    deployed'
        Assert-Contains $result.Text $runtimeRoot
        Assert-True (Test-Path -LiteralPath (Join-Path $customDir 'scripts\upwsh.ps1')) (
            'source deploy missed upwsh.ps1'
        )
        $text = [IO.File]::ReadAllText($customHook)
        Assert-Contains $text (Join-Path $customDir 'profile.ps1')
        Assert-True ($text -notlike "*$runtimeRoot*") "hooked the source tree:`n$text"
    }

    Invoke-InstallTest 'source src directory also works' {
        $customHook = Join-Path $root 'src-profile.ps1'
        $customDir = Join-Path $root 'from-src'
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $runtimeRoot
            '--directory', $customDir
            '--profile', $customHook
        )
        Assert-Equal $result.Code 0
        Assert-True (Test-Path -LiteralPath (Join-Path $customDir 'profile.ps1')) (
            'src deploy missed profile.ps1'
        )
    }

    Invoke-InstallTest 'check does not copy runtime files' {
        $checkDir = Join-Path $root 'check-dir'
        $checkHook = Join-Path $root 'check-profile.ps1'
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $sourceRoot
            '--check'
            '--directory', $checkDir
            '--profile', $checkHook
        )
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    missing'
        Assert-True (-not (Test-Path -LiteralPath $checkDir)) 'check created the runtime directory'
        Assert-True (-not (Test-Path -LiteralPath $checkHook)) 'check created a profile'
    }

    Invoke-InstallTest 'missing source directory exits 1' {
        $missing = Join-Path $root 'no-such-src'
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $missing
            '--directory', (Join-Path $root 'unused')
            '--profile', (Join-Path $root 'unused.ps1')
        )
        Assert-Equal $result.Code 1
        Assert-Contains $result.Text 'missing profile.ps1'
    }

    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
        Invoke-InstallTest 'bootstrap.sh forwards source deploy to pwsh' {
            $sh = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'scripts\bootstrap.sh'))
            $customHook = Join-Path $root 'sh-profile.ps1'
            $customDir = Join-Path $root 'from-sh'
            $previous = $global:LASTEXITCODE
            try {
                $global:LASTEXITCODE = 0
                $output = & bash $sh --source $sourceRoot --directory $customDir --profile $customHook 2>&1 |
                    Out-String
                Assert-Equal $global:LASTEXITCODE 0
                Assert-Contains $output 'state    deployed'
                Assert-True (Test-Path -LiteralPath (Join-Path $customDir 'profile.ps1')) (
                    'bootstrap.sh missed profile.ps1'
                )
            } finally {
                $global:LASTEXITCODE = $previous
            }
        }
    }
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) of $($script:Passed + $script:Failures.Count) install tests failed."
}

Write-Output "$script:Passed install tests passed."
