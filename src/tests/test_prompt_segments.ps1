$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}
$runtime = Join-Path $HOME 'runtime'
[void][IO.Directory]::CreateDirectory((Join-Path $runtime 'themes'))
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach ($file in @('theme.psm1', 'prompt.psm1', 'path.psm1', 'path_convert.ps1')) {
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination $runtime
}
Copy-Item -LiteralPath (Join-Path $source 'themes\pure-classic.json') -Destination (Join-Path $runtime 'themes')
Import-Module (Join-Path $runtime 'path.psm1') -DisableNameChecking
Import-Module (Join-Path $runtime 'theme.psm1')
Import-Module (Join-Path $runtime 'prompt.psm1')
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
function Test-Segments {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++ } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}
function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}
function Use-Theme {
    param($Data)
    [IO.File]::WriteAllText((Join-Path $runtime 'themes\Segments.json'), ($Data | ConvertTo-Json -Depth 8))
    $null = Set-UpwshTheme 'Segments'
}
function New-Theme {
    @{
        Version = 2; Name = 'Segments'
        Order = @('directory', 'dirArrow', 'git', 'gitArrow', 'duration', 'timeArrow', 'exitCode', 'errorArrow', 'symbol')
        Modules = @{
            directory = @{ Foreground = '#FFFFFF'; Background = '#112233' }
            git = @{ Background = '#223344' }
            duration = @{ Background = '#334455'; MinMs = 2000 }
            exitCode = @{ Background = '#445566'; Prefix = '['; Suffix = ']' }
            symbol = @{ Text = '>'; Background = 'transparent'; Failure = @{ Text = '!'; Background = '#556677' } }
            dirArrow = @{ Type = 'text'; Text = '|'; AttachTo = @('directory'); Foreground = 'previous.background'; Background = 'next.background' }
            gitArrow = @{ Type = 'text'; Text = '|'; AttachTo = @('git'); Foreground = 'previous.background'; Background = 'next.background' }
            timeArrow = @{ Type = 'text'; Text = '|'; AttachTo = @('duration'); Foreground = 'previous.background'; Background = 'next.background' }
            errorArrow = @{ Type = 'text'; Text = '|'; AttachTo = @('exitCode'); Foreground = 'previous.background'; Background = 'next.background' }
        }
    }
}
$repo = Join-Path $HOME 'repo'
[void][IO.Directory]::CreateDirectory((Join-Path $repo '.git'))
[IO.File]::WriteAllText((Join-Path $repo '.git\HEAD'), 'ref: refs/heads/dev')
$outside = Join-Path $HOME 'outside'
[void][IO.Directory]::CreateDirectory($outside)
$esc = [char]27
Push-Location $repo
try {
    Test-Segments 'all Git duration and exit combinations hide attached connectors and padding' {
        Use-Theme (New-Theme)
        foreach ($inRepo in @($true, $false)) {
            Set-Location $(if ($inRepo) { $repo } else { $outside })
            foreach ($success in @($true, $false)) {
                foreach ($ms in @(0, 1999, 2000, 2345)) {
                    $expected = if ($inRepo) { 'repo|dev|' } else { 'outside|' }
                    if ($ms -ge 2000) { $expected += "2s$($ms - 2000)ms|" }
                    if ($success) { $expected += '>' } else { $expected += '[7]|!' }
                    Assert-Equal (Get-UpwshPromptText -Succeeded $success -ExitCode 7 -DurationMs $ms -Color Never) $expected
                }
            }
        }
    }
    Test-Segments 'connectors use nearest visible backgrounds and effective failure style' {
        Set-Location $outside
        Use-Theme (New-Theme)
        $text = Get-UpwshPromptText -Color Always
        Assert-True ($text.Contains("$esc[0;38;2;17;34;51;49m|")) 'hidden modules prevented transparent tail'
        $text = Get-UpwshPromptText -DurationMs 2345 -Color Always
        Assert-True ($text.Contains("$esc[0;38;2;17;34;51;48;2;51;68;85m|")) 'connector did not skip hidden Git'
        $text = Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 2345 -Color Always
        Assert-True ($text.Contains("$esc[0;38;2;51;68;85;48;2;68;85;102m|")) 'time-to-error color mismatch'
        Assert-True ($text.Contains("$esc[0;38;2;68;85;102;48;2;85;102;119m|")) 'connector ignored failure background'
        Assert-True ($text.EndsWith("$esc[0m")) 'background leaked into input'
    }
    Test-Segments 'user host and at have independent styles and visibility' {
        $data = New-Theme
        $data.Order = @('user', 'at', 'host')
        $data.Modules = @{
            user = @{ Foreground = '#010203'; Background = '#040506' }
            host = @{ Foreground = '#070809'; Background = 'transparent' }
            at = @{ Type = 'text'; Text = '@'; AttachTo = @('user', 'host') }
        }
        Use-Theme $data
        $text = Get-UpwshPromptText -Color Always
        Assert-True ($text.Contains("$esc[0;38;2;1;2;3;48;2;4;5;6m$env:USERNAME")) 'user style not independent'
        Assert-True ($text.Contains("$esc[0;38;2;7;8;9;49m")) 'host did not reset background'
        $data.Modules.host.Enabled = $false
        Use-Theme $data
        Assert-Equal (Get-UpwshPromptText -Color Never) $env:USERNAME
    }
    Test-Segments 'text-only layouts have terminal-default neighbor fallbacks and repeat literally' {
        Use-Theme @{ Version = 2; Name = 'Segments'; Order = @('cap', 'gap', 'cap'); Modules = @{
            cap = @{ Type = 'text'; Text = '>'; Foreground = 'previous.background'; Background = 'next.background' }
            gap = @{ Type = 'text'; Text = ' ' }
        } }
        Assert-Equal (Get-UpwshPromptText -Color Never) '> >'
        Assert-True ((Get-UpwshPromptText -Color Always).Contains("$esc[0;39;49m>")) 'default fallback missing'
    }
    Test-Segments 'paired triangle and notch share anchors and do not become each others neighbors' {
        $data = New-Theme
        $data.Order = @('directory', 'triangle', 'notch', 'git', 'symbol')
        $data.Modules.Remove('dirArrow'); $data.Modules.Remove('gitArrow'); $data.Modules.Remove('timeArrow'); $data.Modules.Remove('errorArrow')
        $data.Modules.triangle = @{ Type = 'text'; Text = ''; Foreground = 'previous.background'; Background = 'next.background'; AttachTo = @('directory', 'git') }
        $data.Modules.notch = @{ Type = 'text'; Text = ''; Foreground = 'previous.background'; Background = 'next.background'; AttachTo = @('directory', 'git') }
        Use-Theme $data
        Set-Location $repo
        Assert-Equal (Get-UpwshPromptText -Color Never) 'repodev>'
        $text = Get-UpwshPromptText -Color Always
        Assert-True ($text.Contains("$esc[0;38;2;17;34;51;48;2;34;51;68m$esc[0;38;2;17;34;51;48;2;34;51;68m")) 'text segments altered neighbor colors'
        Set-Location $outside
        Assert-Equal (Get-UpwshPromptText -Color Never) 'outside>'
    }
    Test-Segments 'duration requires positive elapsed time and success/failure conditions compose' {
        $data = New-Theme
        $data.Modules.duration.MinMs = 0
        $data.Modules.duration.When = 'failure'
        Use-Theme $data
        Assert-Equal (Get-UpwshPromptText -DurationMs 3000 -Color Never) 'outside|>'
        Assert-Equal (Get-UpwshPromptText -Succeeded $false -DurationMs 0 -Color Never) 'outside|[1]|!'
        Assert-Equal (Get-UpwshPromptText -Succeeded $false -DurationMs 1 -Color Never) 'outside|0s1ms|[1]|!'
    }
    Test-Segments 'exitCode can explicitly show zero on success and condition text follows it' {
        $data = New-Theme
        $data.Modules.exitCode.When = 'always'
        $data.Modules.dirArrow.When = 'failure'
        Use-Theme $data
        Assert-Equal (Get-UpwshPromptText -ExitCode 9 -Color Never) 'outside[0]|>'
        Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 0 -Color Never) 'outside|[1]|!'
    }
    Test-Segments 'disabled or conditionally hidden Git is not queried and repeated Git is queried once' {
        $module = (Get-Command Get-UpwshPromptText).Module
        $saved = & $module { (Get-Command Get-PromptGitBranch).ScriptBlock }
        try {
            & $module { $script:Queries = 0; Set-Item Function:Get-PromptGitBranch { $script:Queries++; return 'dev' } }
            $data = New-Theme
            $data.Modules.git.When = 'failure'
            Use-Theme $data
            $null = Get-UpwshPromptText -Color Never
            Assert-Equal (& $module { $script:Queries }) 0
            $data.Modules.git.When = 'always'
            $data.Order = @('git', 'git')
            foreach ($id in @('dirArrow', 'gitArrow', 'timeArrow', 'errorArrow')) { $data.Modules.Remove($id) }
            Use-Theme $data
            Assert-Equal (Get-UpwshPromptText -Color Never) 'devdev'
            Assert-Equal (& $module { $script:Queries }) 1
            $data.Modules.git.Enabled = $false
            Use-Theme $data
            Assert-Equal (Get-UpwshPromptText -Color Never) ''
            Assert-Equal (& $module { $script:Queries }) 1
        } finally { & $module { param($body) Set-Item Function:Get-PromptGitBranch $body } $saved }
    }
    Test-Segments 'a repeated connector resolves colors separately at each occurrence' {
        Use-Theme @{ Version = 2; Name = 'Segments'; Order = @('user', 'join', 'host', 'join', 'directory'); Modules = @{
            user = @{ Background = '#112233' }
            host = @{ Background = '#223344' }
            directory = @{ Background = '#334455' }
            join = @{ Type = 'text'; Text = '>'; Foreground = 'previous.background'; Background = 'next.background' }
        } }
        $text = Get-UpwshPromptText -Color Always
        Assert-True ($text.Contains("$esc[0;38;2;17;34;51;48;2;34;51;68m>")) 'first occurrence used wrong neighbors'
        Assert-True ($text.Contains("$esc[0;38;2;34;51;68;48;2;51;68;85m>")) 'second occurrence reused first neighbors'
    }
    Test-Segments 'all conditional data hidden leaves no decorations or padding' {
        $data = New-Theme
        $data.Modules.directory.Enabled = $false
        $data.Modules.git.Enabled = $false
        $data.Modules.symbol.Enabled = $false
        Use-Theme $data
        Assert-Equal (Get-UpwshPromptText -DurationMs 1999 -Color Never) ''
        Assert-Equal (Get-UpwshPromptText -DurationMs 1999 -Color Always) "$esc[0m"
    }
    Test-Segments 'provider locations hide Git and its connectors' {
        Use-Theme (New-Theme)
        Push-Location Env:\
        try { Assert-Equal (Get-UpwshPromptText -Color Never) 'Env:\|>' } finally { Pop-Location }
    }
    Test-Segments 'literal text is never evaluated as PowerShell and NoColor strips all SGR' {
        Use-Theme @{ Version = 2; Name = 'Segments'; Order = @('literal'); Modules = @{
            literal = @{ Type = 'text'; Text = '$(throw "do not execute")'; Background = '#102030' }
        } }
        Assert-Equal (Get-UpwshPromptText -Color Never) '$(throw "do not execute")'
        $saved = $env:NO_COLOR
        try {
            $env:NO_COLOR = '1'
            Assert-Equal (Get-UpwshPromptText -Color Auto) '$(throw "do not execute")'
        } finally { $env:NO_COLOR = $saved }
    }
    Test-Segments 'AddNewline is opt-in, resets background and never accumulates on repeated renders' {
        $data = New-Theme
        Use-Theme $data
        $plain = Get-UpwshPromptText -Color Never
        $colored = Get-UpwshPromptText -Color Always
        Assert-Equal (Get-UpwshTheme).AddNewline $false
        $data.AddNewline = $true
        Use-Theme $data
        for ($i = 0; $i -lt 3; $i++) {
            Assert-Equal (Get-UpwshPromptText -Color Never) ("`n" + $plain)
            Assert-Equal (Get-UpwshPromptText -Color Always) ("$esc[0m`n" + $colored)
        }
        $data.AddNewline = $false
        Use-Theme $data
        Assert-Equal (Get-UpwshPromptText -Color Never) $plain
    }
    Test-Segments 'failed render never mutates the next successful symbol style' {
        Use-Theme (New-Theme)
        $before = Get-UpwshPromptText -Color Always
        $null = Get-UpwshPromptText -Succeeded $false -ExitCode 7 -Color Always
        Assert-Equal (Get-UpwshPromptText -Color Always) $before
        Assert-Equal (Get-UpwshTheme).Modules.symbol.Background 'transparent'
    }
} finally { Pop-Location }
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) segment tests failed."
}
Write-Output "$script:Passed segment tests passed."
