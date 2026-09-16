$ErrorActionPreference = 'Stop'

$upwsh = Join-Path $PSScriptRoot '..\scripts\upwsh.ps1'
$sourceProfile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\profile.ps1'))
$root = Join-Path ([IO.Path]::GetTempPath()) (
    'pwsh-upwsh-' + [Guid]::NewGuid().ToString('N')
)
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
    param([string[]]$Tokens = @())

    $previous = $global:LASTEXITCODE
    $savedHome = $env:UPWSH_HOME
    $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
    try {
        $env:UPWSH_HOME = $root
        $env:UPWSH_SKIP_PERSIST_PATH = '1'
        $global:LASTEXITCODE = 0
        $output = & $upwsh @Tokens 2>&1 | Out-String
        [pscustomobject]@{
            Text = $output
            Code = $global:LASTEXITCODE
        }
    } finally {
        $global:LASTEXITCODE = $previous
        $env:UPWSH_HOME = $savedHome
        $env:UPWSH_SKIP_PERSIST_PATH = $savedSkip
    }
}

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $hook = Join-Path $root 'profile.ps1'
    $bin = Join-Path $root 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null

    Invoke-UpwshTest 'no args prints usage' {
        $result = Invoke-Upwsh
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'upwsh'
        Assert-Contains $result.Text '--load'
        Assert-Contains $result.Text '-l'
        Assert-Contains $result.Text '--tool'
        Assert-Contains $result.Text '-t'
        Assert-Contains $result.Text '--check'
        Assert-Contains $result.Text '--uninstall'
        Assert-Contains $result.Text '--unload'
        Assert-Contains $result.Text '--deploy'
        Assert-Contains $result.Text '--current-host'
        Assert-Contains $result.Text '--profile'
        Assert-Contains $result.Text '--force'
        Assert-True ($result.Text -cnotmatch '-Check') 'help still uses -Check'
        Assert-True ($result.Text -cnotmatch '--install') 'help still lists --install'
        Assert-True ($result.Text -cnotmatch '--only') 'help still lists --only'
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
        Assert-Contains $result.Text '--load'
    }

    Invoke-UpwshTest 'load and tool together is an error' {
        $result = Invoke-Upwsh -Tokens @('-l', '-t')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'use only one of --load, --unload, or --tool'
    }

    Invoke-UpwshTest 'load and unload together is an error' {
        $result = Invoke-Upwsh -Tokens @('--load', '--unload')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'use only one of --load, --unload, or --tool'
    }

    Invoke-UpwshTest 'load check uses a custom profile path' {
        $result = Invoke-Upwsh -Tokens @('--load', '--check', '--profile', $hook)
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    missing'
        Assert-Contains $result.Text $hook
        Assert-Contains $result.Text $sourceProfile
        Assert-True (-not (Test-Path -LiteralPath $hook)) 'load --check created a profile'
    }

    Invoke-UpwshTest 'load short flag hooks the custom profile' {
        $result = Invoke-Upwsh -Tokens @('-l', '-p', $hook)
        Assert-Equal $result.Code 0
        $text = [IO.File]::ReadAllText($hook)
        Assert-Contains $result.Text 'state    installed'
        Assert-Contains $text '# >>> unixify-powershell >>>'
        Assert-Contains $text $sourceProfile
    }

    Invoke-UpwshTest 'load subcommand check reports installed' {
        $result = Invoke-Upwsh -Tokens @('load', '-c', '--profile', $hook)
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    installed'
    }

    Invoke-UpwshTest 'load -u is not unload' {
        $result = Invoke-Upwsh -Tokens @('--load', '-u', '--profile', $hook)
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text '--uninstall is only valid with --tool'
    }

    Invoke-UpwshTest 'unload removes the hook' {
        $result = Invoke-Upwsh -Tokens @('unload', '--profile', $hook)
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    removed'
        $text = [IO.File]::ReadAllText($hook)
        Assert-True ($text -notlike '*unixify-powershell*') "unload left the marker:`n$text"
    }

    Invoke-UpwshTest 'tool options are rejected on load' {
        $result = Invoke-Upwsh -Tokens @('--load', '--force', '--profile', $hook)
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text '--force is only valid with --tool'
    }

    Invoke-UpwshTest 'tool uninstall without a name prints usage' {
        $result = Invoke-Upwsh -Tokens @('--tool', '--uninstall')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'missing tool name'
    }

    Invoke-UpwshTest 'tool --install is unknown' {
        $result = Invoke-Upwsh -Tokens @('--tool', '--install')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'unknown option: --install'
    }

    Invoke-UpwshTest 'load options are rejected on tool' {
        $result = Invoke-Upwsh -Tokens @('--tool', '--deploy')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text '--deploy is only valid with --load'
    }

    Invoke-UpwshTest 'tool uninstall removes a named exe' {
        $exe = Join-Path $bin 'eza.exe'
        [IO.File]::WriteAllText($exe, 'stub')
        $result = Invoke-Upwsh -Tokens @(
            '--tool', '--uninstall', 'eza'
        )
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'removed'
        Assert-True (-not (Test-Path -LiteralPath $exe)) "uninstall left $exe"
    }

    Invoke-UpwshTest 'tool check names limit the list' {
        $result = Invoke-Upwsh -Tokens @('--tool', '--check', 'eza')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'dir'
        Assert-Contains $result.Text 'eza'
        Assert-Contains $result.Text 'missing'
        Assert-True ($result.Text -notmatch 'bat') 'tool check leaked extra tools'
    }

    Invoke-UpwshTest 'tool short flags check the upwsh bin' {
        $result = Invoke-Upwsh -Tokens @('-t', '-c', 'rg')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'rg'
        Assert-Contains $result.Text 'dir'
    }

    Invoke-UpwshTest 'profile function forwards to the script' {
        $savedHome = $env:UPWSH_HOME
        try {
            $env:UPWSH_HOME = $root
            . $sourceProfile
            $output = upwsh --help | Out-String
            Assert-Contains $output '--load'
            Assert-Contains $output '--tool'
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
