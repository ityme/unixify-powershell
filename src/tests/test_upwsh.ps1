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
    $savedProfile = $env:UPWSH_PROFILE
    $savedSkip = $env:UPWSH_SKIP_PERSIST_PATH
    try {
        $env:UPWSH_HOME = $root
        $env:UPWSH_PROFILE = Join-Path $root 'profile.ps1'
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
        $env:UPWSH_PROFILE = $savedProfile
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
        Assert-Contains $result.Text 'load'
        Assert-Contains $result.Text 'unload'
        Assert-Contains $result.Text 'tool install'
        Assert-Contains $result.Text 'tool uninstall'
        Assert-Contains $result.Text 'tool list'
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
        Assert-Contains $result.Text 'use only one of load, unload, or tool'
    }

    Invoke-UpwshTest 'load and unload together is an error' {
        $result = Invoke-Upwsh -Tokens @('load', 'unload')
        Assert-Equal $result.Code 2
        Assert-Contains $result.Text 'use only one of load, unload, or tool'
    }

    Invoke-UpwshTest 'load hooks the profile' {
        $result = Invoke-Upwsh -Tokens @('load')
        Assert-Equal $result.Code 0
        Assert-Contains $result.Text 'state    installed'
        Assert-Contains $result.Text $hook
        Assert-Contains $result.Text $sourceProfile
        $text = [IO.File]::ReadAllText($hook)
        Assert-Contains $text '# >>> unixify-powershell >>>'
        Assert-Contains $text $sourceProfile
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

    Invoke-UpwshTest 'tool uninstall removes a named exe' {
        $exe = Join-Path $bin 'eza.exe'
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
            $env:PATH = $bin
            $result = Invoke-Upwsh -Tokens @('tool', 'list', 'eza')
            Assert-Equal $result.Code 0
            Assert-Contains $result.Text 'eza'
            Assert-Contains $result.Text 'missing'
            Assert-True ($result.Text -notmatch 'bat') 'tool list leaked extra tools'
            Assert-True ($result.Text -notmatch 'dir') 'tool list printed install dir'
        } finally {
            $env:PATH = $savedPath
        }
    }

    Invoke-UpwshTest 'tool list reports a command on PATH' {
        $exe = Join-Path $bin 'eza.exe'
        [IO.File]::WriteAllText($exe, 'stub')
        $savedPath = $env:PATH
        try {
            $env:PATH = $bin
            $result = Invoke-Upwsh -Tokens @('tool', 'list', 'eza')
            Assert-Equal $result.Code 0
            Assert-Contains $result.Text 'eza'
            Assert-Contains $result.Text 'ok'
            Assert-True ($result.Text -notmatch 'missing') 'tool list missed an on-PATH command'
        } finally {
            $env:PATH = $savedPath
        }
    }

    Invoke-UpwshTest 'tool short flags list the upwsh tools' {
        $savedPath = $env:PATH
        try {
            $env:PATH = $bin
            $result = Invoke-Upwsh -Tokens @('-t', 'list', 'rg')
            Assert-Equal $result.Code 0
            Assert-Contains $result.Text 'rg'
            Assert-Contains $result.Text 'missing'
        } finally {
            $env:PATH = $savedPath
        }
    }

    Invoke-UpwshTest 'profile function forwards to the script' {
        $savedHome = $env:UPWSH_HOME
        try {
            $env:UPWSH_HOME = $root
            . $sourceProfile
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

