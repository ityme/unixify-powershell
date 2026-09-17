$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}

$upwsh = Join-Path $PSScriptRoot '..\scripts\upwsh.ps1'
$sourceProfile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\profile.ps1'))
$root = Join-Path ([IO.Path]::GetTempPath()) (
    'pwsh-upwsh-' + [Guid]::NewGuid().ToString('N')
)
$installHome = Join-Path $HOME '.config\upwsh'
$installedProfile = Join-Path $installHome 'profile.ps1'
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()

function Invoke-UpwshTest {
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

function Invoke-Upwsh {
    param(
        [string[]]$Tokens = @(),
        [switch]$LoadSession
    )

    $previous = $global:LASTEXITCODE
    $savedHome = $env:UPWSH_HOME
    $savedProfile = $env:UPWSH_PROFILE
    $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
    $savedSkipSession = $env:UPWSH_SKIP_SESSION_LOAD
    $savedPath = $env:PATH
    try {
        $env:UPWSH_HOME = Split-Path -Parent $sourceProfile
        $env:UPWSH_PROFILE = Join-Path $root 'profile.ps1'
        $env:UPWSH_SKIP_PERSIST_PATH = '1'
        if ($LoadSession) {
            Remove-Item Env:\UPWSH_SKIP_SESSION_LOAD -ErrorAction SilentlyContinue
        } else {
            $env:UPWSH_SKIP_SESSION_LOAD = '1'
        }
        $global:LASTEXITCODE = 0
        $output = & $upwsh @Tokens 2>&1 | Out-String
        [pscustomobject]@{
            Text = $output
            Code = $global:LASTEXITCODE
            Path = $env:PATH
        }
    } finally {
        $global:LASTEXITCODE = $previous
        $env:UPWSH_HOME = $savedHome
        $env:UPWSH_PROFILE = $savedProfile
        $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
        $env:UPWSH_SKIP_SESSION_LOAD = $savedSkipSession
        $env:PATH = $savedPath
    }
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $hook = Join-Path $root 'profile.ps1'
    $bin = Join-Path $installHome 'bin'
    $toolBin = Join-Path $installHome 'tool\bin'
    New-Item -ItemType Directory -Path $bin, $toolBin -Force | Out-Null
    $shim = Join-Path $bin 'upwsh.cmd'

    Invoke-UpwshTest 'no args prints usage' {
        $result = Invoke-Upwsh
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'upwsh'
        Assert-Contains $result.Text 'load'
        Assert-Contains $result.Text 'unload'
        Assert-Contains $result.Text 'tool install'
        Assert-Contains $result.Text 'tool uninstall'
        Assert-Contains $result.Text 'tool list'
        Assert-Contains $result.Text '   install'
        Assert-Contains $result.Text '   uninstall'
        Assert-Contains $result.Text '   update'
        Assert-True ($result.Text -cnotmatch '--profile') 'help still lists --profile'
        Assert-True ($result.Text -cnotmatch '--check') 'help still lists --check'
        Assert-True ($result.Text -cnotmatch '--deploy') 'help still lists --deploy'
        Assert-True ($result.Text -cnotmatch '--force') 'help still lists --force'
        Assert-True ($result.Text -cnotmatch '--only') 'help still lists --only'
        Assert-True ($result.Text -cnotmatch '--current-host') 'help still lists --current-host'
    }

    Invoke-UpwshTest 'help flag prints usage' {
        $result = Invoke-Upwsh -Tokens @('--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'These are common upwsh commands'
        $result = Invoke-Upwsh -Tokens @('-h')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text "hook the current user's pwsh"
    }

    Invoke-UpwshTest 'unknown option prints usage and exits 2' {
        $result = Invoke-Upwsh -Tokens @('--nope')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option'
        Assert-Contains $result.Text 'load'
    }

    Invoke-UpwshTest 'load and tool together is an error' {
        $result = Invoke-Upwsh -Tokens @('-l', '-t')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'use only one of load, unload, tool, install, uninstall, or update'
    }

    Invoke-UpwshTest 'load and unload together is an error' {
        $result = Invoke-Upwsh -Tokens @('load', 'unload')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'use only one of load, unload, tool, install, uninstall, or update'
    }

    Invoke-UpwshTest 'load before install fails without writing a hook' {
        $failed = $false
        try { Invoke-Upwsh -Tokens @('load') | Out-Null } catch { $failed = $true }
        Assert-True $failed 'load unexpectedly used the source tree'
        Assert-True (-not (Test-Path -LiteralPath $hook)) 'failed load wrote a hook'
    }

    Invoke-UpwshTest 'install deploys before load' {
        $result = Invoke-Upwsh -Tokens @('install')
        Assert-Equal $result.Code 0
        Assert-True (Test-Path -LiteralPath $installedProfile) 'install missed runtime'
    }

    Invoke-UpwshTest 'load hooks the installed profile' {
        $result = Invoke-Upwsh -Tokens @('load')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    installed'
        Assert-Contains $result.Text $hook
        Assert-Contains $result.Text $installedProfile
        Assert-Contains $result.Text 'home'
        Assert-Contains $result.Text $installHome
        Assert-Contains $result.Text 'path'
        Assert-Contains $result.Text '%UPWSH_HOME%\bin'
        Assert-Contains $result.Text '%UPWSH_HOME%\tool\bin'
        Assert-Contains $result.Text 'cmd'
        Assert-True (Test-Path -LiteralPath $shim -PathType Leaf) 'load missed upwsh.cmd'
        $text = [IO.File]::ReadAllText($hook)
        Assert-Contains $text '# >>> unixify-powershell >>>'
        Assert-Contains $text $installedProfile
        Assert-True (-not $text.Contains($sourceProfile)) 'load hooked source tree'
    }

    Invoke-UpwshTest 'load short flag hooks the profile' {
        $result = Invoke-Upwsh -Tokens @('-l')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    installed'
    }

    Invoke-UpwshTest 'load again reports installed' {
        $result = Invoke-Upwsh -Tokens @('load')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    installed'
    }

    Invoke-UpwshTest 'load -u is unknown' {
        $result = Invoke-Upwsh -Tokens @('load', '-u')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option: -u'
    }

    Invoke-UpwshTest 'unload removes the hook' {
        $result = Invoke-Upwsh -Tokens @('unload')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    removed'
        Assert-True ($result.Text -notlike '*home    removed*') 'unload removed UPWSH_HOME'
        Assert-True ($result.Text -notlike '*path    removed*') 'unload removed Path'
        Assert-True (Test-Path -LiteralPath $shim -PathType Leaf) 'unload deleted upwsh.cmd'
        $text = [IO.File]::ReadAllText($hook)
        Assert-True ($text -notlike '*unixify-powershell*') "unload left the marker:`n$text"
    }

    Invoke-UpwshTest 'tool options are rejected on load' {
        $result = Invoke-Upwsh -Tokens @('load', '--force')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option: --force'
    }

    Invoke-UpwshTest 'load --profile is unknown' {
        $result = Invoke-Upwsh -Tokens @('load', '--profile', $hook)
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option: --profile'
    }

    Invoke-UpwshTest 'tool without a command prints usage' {
        $result = Invoke-Upwsh -Tokens @('tool')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'missing tool command'
    }

    Invoke-UpwshTest 'tool uninstall without a name prints usage' {
        $result = Invoke-Upwsh -Tokens @('tool', 'uninstall')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'missing tool name'
    }

    Invoke-UpwshTest 'unknown tool command prints usage' {
        $result = Invoke-Upwsh -Tokens @('tool', '--deploy')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown tool command: --deploy'
    }

    Invoke-UpwshTest 'install help is forwarded' {
        $result = Invoke-Upwsh -Tokens @('install', '--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'install.ps1'
    }

    Invoke-UpwshTest 'uninstall help is forwarded' {
        $result = Invoke-Upwsh -Tokens @('uninstall', '--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'uninstall.ps1'
    }

    Invoke-UpwshTest 'update help is forwarded' {
        $result = Invoke-Upwsh -Tokens @('update', '--help')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'update.ps1'
    }

    Invoke-UpwshTest 'tool uninstall removes a named exe' {
        $exe = Join-Path $toolBin 'eza.exe'
        [IO.File]::WriteAllText($exe, 'stub')
        $result = Invoke-Upwsh -Tokens @(
            'tool', 'uninstall', 'eza'
        )
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'removed'
        Assert-True (-not (Test-Path -LiteralPath $exe)) "uninstall left $exe"
    }

    Invoke-UpwshTest 'tool list names limit the list' {
        $savedPath = $env:PATH
        try {
            $env:PATH = $toolBin
            $result = Invoke-Upwsh -Tokens @('tool', 'list', 'eza')
            Assert-Equal $result.Code 0
            Assert-Contains $result.Text 'eza'
            Assert-Contains $result.Text 'uninstalled'
            Assert-True ($result.Text -notmatch 'bat') 'tool list leaked extra tools'
            Assert-True ($result.Text -notmatch 'dir') 'tool list printed install dir'
        } finally {
            $env:PATH = $savedPath
        }
    }

    Invoke-UpwshTest 'tool list reports a command on PATH' {
        $exe = Join-Path $toolBin 'eza.exe'
        [IO.File]::WriteAllText($exe, 'stub')
        $savedPath = $env:PATH
        try {
            $env:PATH = $toolBin
            $result = Invoke-Upwsh -Tokens @('tool', 'list', 'eza')
            Assert-Equal $result.Code 0
            Assert-Contains $result.Text 'eza'
            Assert-Contains $result.Text 'installed'
            Assert-True ($result.Text -notmatch 'uninstalled') 'tool list missed an on-PATH command'
        } finally {
            $env:PATH = $savedPath
        }
    }

    Invoke-UpwshTest 'tool short flags list the upwsh tools' {
        $savedPath = $env:PATH
        try {
            $env:PATH = $toolBin
            $result = Invoke-Upwsh -Tokens @('-t', 'list', 'rg')
            Assert-Equal $result.Code 0
            Assert-Contains $result.Text 'rg'
            Assert-Contains $result.Text 'uninstalled'
        } finally {
            $env:PATH = $savedPath
        }
    }

    Invoke-UpwshTest 'load applies only the installed runtime in this session' {
        $sentinel = Join-Path $installHome 'custom\zz-installed.ps1'
        [IO.File]::WriteAllText($sentinel, 'Set-Alias -Name installed_only -Value Get-Date -Scope Global -Force')
        $result = Invoke-Upwsh -LoadSession -Tokens @('load')
        Assert-Equal (Get-Command installed_only -ErrorAction Stop).Definition 'Get-Date'
        Assert-Equal $result.Code 0
        $command = Get-Command vim -ErrorAction Stop
        Assert-Equal $command.CommandType.ToString() 'Alias'
        Assert-Equal $command.Definition 'nvim'
        Assert-True ($result.Path -like "*$bin*") 'load did not add bin to PATH'
        Assert-True ($result.Path -like "*$toolBin*") 'load did not add tool\\bin to PATH'
        Assert-True (Test-Path -LiteralPath $shim -PathType Leaf) 'session load missed upwsh.cmd'
    }

    Invoke-UpwshTest 'profile function forwards to the script' {
        $savedHome = $env:UPWSH_HOME
        try {
            $env:UPWSH_HOME = $installHome
            . $installedProfile
            $output = upwsh --help | Out-String
            Assert-Contains $output 'load'
            Assert-Contains $output 'tool install'
            $command = Get-Command upwsh -ErrorAction Stop
            Assert-Equal $command.CommandType.ToString() 'Function'
        } finally {
            $env:UPWSH_HOME = $savedHome
        }
    }
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) of $($script:Passed + $script:Failures.Count) upwsh tests failed."
}

Write-Output "$script:Passed upwsh tests passed."

