$ErrorActionPreference = 'Stop'

$installer = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\install.ps1'))
$uninstaller = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\uninstall.ps1'))
$updater = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\update.ps1'))
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
    $savedSkipRelaunch = $env:UPWSH_SKIP_RELAUNCH
    $savedPath = $env:PATH
    try {
        $env:UPWSH_REPO = $null
        $env:UPWSH_REF = $null
        $env:UPWSH_SOURCE = $null
        $env:UPWSH_SKIP_PERSIST_PATH = '1'
        $env:UPWSH_SKIP_SESSION_LOAD = '1'
        $env:UPWSH_SKIP_RELAUNCH = '1'
        $global:LASTEXITCODE = 0
        $output = & $installer @Tokens 2>&1 | Out-String
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
        $env:UPWSH_SKIP_RELAUNCH = $savedSkipRelaunch
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
        Assert-Contains $result.Text '%UPWSH_HOME%\tool\bin'
        Assert-True (Test-Path -LiteralPath (Join-Path $deployRoot 'bin\upwsh.cmd') -PathType Leaf) (
            'install missed upwsh.cmd'
        )
    }

    Invoke-InstallTest 'help flag prints usage' {
        $result = Invoke-Bootstrap -Tokens @('--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'unixify-powershell'
        Assert-Contains $result.Text 'UPWSH_HOME'
        Assert-Contains $result.Text '--source'
        Assert-Contains $result.Text 'irm'
        Assert-Contains $result.Text 'install.ps1'
        Assert-True ($result.Text -cnotmatch 'bootstrap.ps1') 'help still lists bootstrap.ps1'
    }

    Invoke-InstallTest 'uninstall help prints usage' {
        $previous = $global:LASTEXITCODE
        try {
            $global:LASTEXITCODE = 0
            $output = & $uninstaller --help 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'uninstall.ps1'
            Assert-Contains $output 'Unload first'
            Assert-Contains $output '--keep-custom'
        } finally {
            $global:LASTEXITCODE = $previous
        }
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
            $output = & $installer --profile $envHook 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'state    deployed'
            Assert-True (Test-Path -LiteralPath (Join-Path $envDir 'profile.ps1')) (
                'UPWSH_HOME missed profile.ps1'
            )
            Assert-Contains $output 'state    installed'
            Assert-Contains $output '%UPWSH_HOME%\bin'
            Assert-Contains $output '%UPWSH_HOME%\tool\bin'
            Assert-True (Test-Path -LiteralPath (Join-Path $envDir 'bin\upwsh.cmd') -PathType Leaf) (
                'UPWSH_HOME missed upwsh.cmd'
            )
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

    Invoke-InstallTest 'uninstall unloads then deletes the install tree' {
        $env:UPWSH_HOME = $deployRoot
        Invoke-Bootstrap -Tokens @('--profile', $hook) | Out-Null
        $deployedUninstall = Join-Path $deployRoot 'scripts\uninstall.ps1'
        Assert-True (Test-Path -LiteralPath $deployedUninstall -PathType Leaf) (
            'deploy missed uninstall.ps1'
        )
        $previous = $global:LASTEXITCODE
        $savedHome = $env:UPWSH_HOME
        $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
        $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
        $savedSkipRelaunch = $env:UPWSH_SKIP_RELAUNCH
        $savedPath = $env:PATH
        try {
            $env:UPWSH_HOME = $deployRoot
            $env:UPWSH_SKIP_PERSIST_PATH = '1'
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
            $env:UPWSH_SKIP_RELAUNCH = '1'
            $global:LASTEXITCODE = 0
            $output = & $deployedUninstall --profile $hook 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'state    removed'
            Assert-Contains $output 'home    removed'
            Assert-Contains $output 'path    removed'
            Assert-Contains $output 'tree     removed'
            Assert-True (-not (Test-Path -LiteralPath $deployRoot)) (
                'uninstall left the install tree'
            )
            $text = [IO.File]::ReadAllText($hook)
            Assert-True ($text -notlike '*unixify-powershell*') (
                "uninstall left the marker:`n$text"
            )
        } finally {
            $env:UPWSH_HOME = $savedHome
            $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
            $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
            $env:UPWSH_SKIP_RELAUNCH = $savedSkipRelaunch
            $env:PATH = $savedPath
            $global:LASTEXITCODE = $previous
        }
    }

    Invoke-InstallTest 'uninstall --check does not delete files' {
        $checkHome = Join-Path $root 'uninstall-check'
        $checkHook = Join-Path $root 'uninstall-check-profile.ps1'
        $env:UPWSH_HOME = $checkHome
        Invoke-Bootstrap -Tokens @('--profile', $checkHook) | Out-Null
        $deployedUninstall = Join-Path $checkHome 'scripts\uninstall.ps1'
        $previous = $global:LASTEXITCODE
        $savedHome = $env:UPWSH_HOME
        $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
        $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
        $savedPath = $env:PATH
        try {
            $env:UPWSH_HOME = $checkHome
            $env:UPWSH_SKIP_PERSIST_PATH = '1'
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
            $global:LASTEXITCODE = 0
            $output = & $deployedUninstall --check --profile $checkHook 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'hook     installed'
            Assert-Contains $output 'tree     present'
            Assert-True (Test-Path -LiteralPath $checkHome) 'check deleted the install tree'
            Assert-True (Test-Path -LiteralPath $checkHook) 'check deleted the profile'
        } finally {
            $env:UPWSH_HOME = $savedHome
            $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
            $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
            $env:PATH = $savedPath
            $global:LASTEXITCODE = $previous
        }
    }

    Invoke-InstallTest 'uninstall --keep-custom leaves custom files' {
        $keepHome = Join-Path $root 'keep-custom'
        $keepHook = Join-Path $root 'keep-custom-profile.ps1'
        $env:UPWSH_HOME = $keepHome
        Invoke-Bootstrap -Tokens @('--profile', $keepHook) | Out-Null
        $customFile = Join-Path $keepHome 'custom\local.ps1'
        New-Item -ItemType Directory -Path (Split-Path -Parent $customFile) -Force | Out-Null
        [IO.File]::WriteAllText($customFile, "Set-Alias -Name zz -Value Get-Date -Scope Global -Force`r`n")
        $deployedUninstall = Join-Path $keepHome 'scripts\uninstall.ps1'
        $previous = $global:LASTEXITCODE
        $savedHome = $env:UPWSH_HOME
        $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
        $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
        $savedSkipRelaunch = $env:UPWSH_SKIP_RELAUNCH
        $savedPath = $env:PATH
        try {
            $env:UPWSH_HOME = $keepHome
            $env:UPWSH_SKIP_PERSIST_PATH = '1'
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
            $env:UPWSH_SKIP_RELAUNCH = '1'
            $global:LASTEXITCODE = 0
            $output = & $deployedUninstall --keep-custom --profile $keepHook 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'custom   kept'
            Assert-True (Test-Path -LiteralPath $customFile -PathType Leaf) (
                'keep-custom deleted local.ps1'
            )
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $keepHome 'profile.ps1'))) (
                'keep-custom left the runtime files'
            )
        } finally {
            $env:UPWSH_HOME = $savedHome
            $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
            $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
            $env:UPWSH_SKIP_RELAUNCH = $savedSkipRelaunch
            $env:PATH = $savedPath
            $global:LASTEXITCODE = $previous
        }
    }

    Invoke-InstallTest 'update keeps custom then reinstalls' {
        $updateHome = Join-Path $root 'update-home'
        $updateHook = Join-Path $root 'update-profile.ps1'
        $env:UPWSH_HOME = $updateHome
        Invoke-Bootstrap -Tokens @('--profile', $updateHook) | Out-Null
        $customFile = Join-Path $updateHome 'custom\local.ps1'
        New-Item -ItemType Directory -Path (Split-Path -Parent $customFile) -Force | Out-Null
        [IO.File]::WriteAllText($customFile, "# keep-me`r`n")
        $previous = $global:LASTEXITCODE
        $savedHome = $env:UPWSH_HOME
        $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
        $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
        $savedSkipRelaunch = $env:UPWSH_SKIP_RELAUNCH
        $savedPath = $env:PATH
        try {
            $env:UPWSH_HOME = $updateHome
            $env:UPWSH_SKIP_PERSIST_PATH = '1'
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
            $env:UPWSH_SKIP_RELAUNCH = '1'
            $global:LASTEXITCODE = 0
            $output = & $updater --source $sourceRoot --profile $updateHook 2>&1 | Out-String
            Assert-Equal $global:LASTEXITCODE 0
            Assert-Contains $output 'custom   kept'
            Assert-Contains $output 'state    deployed'
            Assert-True (Test-Path -LiteralPath (Join-Path $updateHome 'profile.ps1') -PathType Leaf) (
                'update missed profile.ps1'
            )
            Assert-True (Test-Path -LiteralPath $customFile -PathType Leaf) (
                'update deleted custom/local.ps1'
            )
            Assert-Contains ([IO.File]::ReadAllText($customFile)) 'keep-me'
        } finally {
            $env:UPWSH_HOME = $savedHome
            $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
            $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
            $env:UPWSH_SKIP_RELAUNCH = $savedSkipRelaunch
            $env:PATH = $savedPath
            $global:LASTEXITCODE = $previous
        }
    }

    Invoke-InstallTest 'piped install does not exit the host pwsh' {
        $pipeHome = Join-Path $root 'piped-home'
        $pipeHook = Join-Path $root 'piped-profile.ps1'
        $wrapper = Join-Path $root 'piped-wrapper.ps1'
        $lines = @(
            '$ErrorActionPreference = ''Stop'''
            ('$env:UPWSH_HOME = {0}' -f ($pipeHome | ConvertTo-Json))
            '$env:UPWSH_SKIP_PERSIST_PATH = ''1'''
            '$env:UPWSH_SKIP_SESSION_LOAD = ''1'''
            '$env:UPWSH_SKIP_RELAUNCH = ''1'''
            ('$env:UPWSH_SOURCE = {0}' -f ($sourceRoot | ConvertTo-Json))
            ('$env:UPWSH_PROFILE = {0}' -f ($pipeHook | ConvertTo-Json))
            ('iex ([IO.File]::ReadAllText({0}))' -f ($installer | ConvertTo-Json))
            'Write-Output ''AFTER_IEX'''
        )
        [IO.File]::WriteAllText($wrapper, ($lines -join "`r`n"))
        $previous = $global:LASTEXITCODE
        try {
            $global:LASTEXITCODE = 0
            $output = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $wrapper 2>&1 | Out-String
            Assert-Contains $output 'AFTER_IEX'
            Assert-Contains $output 'state    deployed'
            Assert-Contains $output $pipeHook
            Assert-True (
                Test-Path -LiteralPath (Join-Path $pipeHome 'profile.ps1') -PathType Leaf
            ) 'piped install missed profile.ps1'
            Assert-True (Test-Path -LiteralPath $pipeHook -PathType Leaf) (
                'piped install missed the test profile'
            )
            $text = [IO.File]::ReadAllText($pipeHook)
            Assert-Contains $text '# >>> unixify-powershell >>>'
        } finally {
            $global:LASTEXITCODE = $previous
        }
    }

    Invoke-InstallTest 'upwsh -File uninstall relaunches then deletes the tree' {
        $fileHome = Join-Path $root 'file-uninstall'
        $fileHook = Join-Path $root 'file-uninstall-profile.ps1'
        $env:UPWSH_HOME = $fileHome
        Invoke-Bootstrap -Tokens @('--profile', $fileHook) | Out-Null
        $upwshFile = Join-Path $fileHome 'scripts\upwsh.ps1'
        Assert-True (Test-Path -LiteralPath $upwshFile -PathType Leaf) 'deploy missed upwsh.ps1'
        $previous = $global:LASTEXITCODE
        $savedHome = $env:UPWSH_HOME
        $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
        $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
        $savedSkipRelaunch = $env:UPWSH_SKIP_RELAUNCH
        $savedPath = $env:PATH
        try {
            $env:UPWSH_HOME = $fileHome
            $env:UPWSH_SKIP_PERSIST_PATH = '1'
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
            Remove-Item Env:\UPWSH_SKIP_RELAUNCH -ErrorAction SilentlyContinue
            $global:LASTEXITCODE = 0
            $output = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $upwshFile uninstall --profile $fileHook 2>&1 | Out-String
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while (
                (Test-Path -LiteralPath $fileHome) -and
                [DateTime]::UtcNow -lt $deadline
            ) {
                Start-Sleep -Milliseconds 200
            }
            Assert-True (-not (Test-Path -LiteralPath $fileHome)) (
                "-File uninstall left the install tree:`n$output"
            )
            $text = [IO.File]::ReadAllText($fileHook)
            Assert-True ($text -notlike '*unixify-powershell*') (
                "-File uninstall left the marker:`n$text"
            )
        } finally {
            $env:UPWSH_HOME = $savedHome
            $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
            $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
            $env:UPWSH_SKIP_RELAUNCH = $savedSkipRelaunch
            $env:PATH = $savedPath
            $global:LASTEXITCODE = $previous
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
