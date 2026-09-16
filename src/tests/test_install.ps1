$ErrorActionPreference = 'Stop'

$bootstrap = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\bootstrap.ps1'))
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
    $savedRepo = $env:UPWSH_REPO
    $savedRef = $env:UPWSH_REF
    $savedHome = $env:UPWSH_HOME
    $savedSource = $env:UPWSH_SOURCE
    $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
    $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
    $savedPath = $env:PATH
    try {
        $env:UPWSH_REPO = $null
        $env:UPWSH_REF = $null
        $env:UPWSH_SOURCE = $null
        $env:UPWSH_SKIP_PERSIST_PATH = '1'
        $env:UPWSH_SKIP_SESSION_LOAD = '1'
        $global:LASTEXITCODE = 0
        $output = & $bootstrap @Tokens 2>&1 | Out-String
        [pscustomobject]@{
            Text = $output
            Code = $global:LASTEXITCODE
        }
    } finally {
        $global:LASTEXITCODE = $previous
        $env:UPWSH_REPO = $savedRepo
        $env:UPWSH_REF = $savedRef
        $env:UPWSH_HOME = $savedHome
        $env:UPWSH_SOURCE = $savedSource
        $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
        $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
        $env:PATH = $savedPath
    }
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $hook = Join-Path $root 'profile.ps1'
    $deployRoot = Join-Path $root 'deploy'

    Invoke-InstallTest 'no args from this repo deploys sibling runtime' {
        $env:UPWSH_HOME = $deployRoot
        $result = Invoke-Bootstrap -Tokens @(
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
        Assert-Contains $result.Text 'state    installed'
        Assert-Contains $result.Text '%UPWSH_HOME%\bin'
    }

    Invoke-InstallTest 'help flag prints usage' {
        $result = Invoke-Bootstrap -Tokens @('--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'unixify-powershell'
        Assert-Contains $result.Text 'UPWSH_HOME'
        Assert-Contains $result.Text '--source'
        Assert-Contains $result.Text 'irm'
    }

    Invoke-InstallTest 'unknown option prints usage and exits 2' {
        $result = Invoke-Bootstrap -Tokens @('--nope')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option'
        Assert-Contains $result.Text 'UPWSH_HOME'
    }

    Invoke-InstallTest 'UPWSH_HOME deploys to the given path' {
        $envDir = Join-Path $root 'from-env'
        $envHook = Join-Path $root 'env-profile.ps1'
        $previous = $global:LASTEXITCODE
        $saved = $env:UPWSH_HOME
        $savedPath = $env:PATH
        $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
        try {
            $env:UPWSH_HOME = $envDir
            $env:UPWSH_SKIP_PERSIST_PATH = '1'
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
            $global:LASTEXITCODE = 0
            $output = & $bootstrap --profile $envHook 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'state    deployed'
            Assert-True (Test-Path -LiteralPath (Join-Path $envDir 'profile.ps1')) (
                'UPWSH_HOME missed profile.ps1'
            )
            Assert-Contains $output 'state    installed'
            Assert-Contains $output '%UPWSH_HOME%\bin'
        } finally {
            $env:UPWSH_HOME = $saved
            $env:PATH = $savedPath
            $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
            $global:LASTEXITCODE = $previous
        }
    }

    Invoke-InstallTest 'source deploys from a local checkout' {
        $customHook = Join-Path $root 'source-profile.ps1'
        $customDir = Join-Path $root 'from-source'
        $env:UPWSH_HOME = $customDir
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $sourceRoot
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
        $env:UPWSH_HOME = $customDir
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $runtimeRoot
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
        $env:UPWSH_HOME = $checkDir
        $result = Invoke-Bootstrap -Tokens @(
            '--source', $sourceRoot
            '--check'
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
            '--profile', (Join-Path $root 'unused.ps1')
        )
        Assert-Equal $result.Code 1
        Assert-Contains $result.Text 'missing profile.ps1'
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
