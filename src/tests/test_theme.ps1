$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}

$runtime = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installHome = Join-Path $HOME '.config\upwsh'
$entry = Join-Path $installHome 'scripts\upwsh.ps1'
$themes = Join-Path $installHome 'themes'
$selection = Join-Path $installHome 'custom\theme.json'
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Test-Theme {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++ } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Invoke-ThemeCli {
    param([string[]]$Tokens)
    $global:LASTEXITCODE = 0
    $text = & $entry @Tokens 2>&1 | Out-String
    [pscustomobject]@{ Code = $global:LASTEXITCODE; Text = $text }
}
function Get-RenderedPrompt {
    $writer = [Console]::Out
    try {
        [Console]::SetOut([IO.TextWriter]::Null)
        prompt
    } finally { [Console]::SetOut($writer) }
}

& (Join-Path $runtime 'scripts\install.ps1') --source $runtime | Out-Null
Assert-Equal $LASTEXITCODE 0
. (Join-Path $installHome 'profile.ps1')
Push-Location $HOME
try {
    $identity = "$env:USERNAME@$([Environment]::MachineName.ToLowerInvariant().Split('.')[0])"
    $hostName = [Environment]::MachineName.ToLowerInvariant().Split('.')[0]
    Test-Theme 'default theme list marks pure-default active without creating a selection' {
        $result = Invoke-ThemeCli @('theme','list')
        Assert-Equal $result.Code 0
        Assert-True ($result.Text.Contains('* pure-default')) $result.Text
        Assert-True (-not [IO.File]::Exists($selection)) 'list wrote selection'
        Assert-Equal (Get-UpwshPromptText -Color Never) "$identity ~ ❯ "
    }
    Test-Theme 'all bundled themes are installed, documented and render their settings' {
        $expected = @('colorful-blue', 'colorful-cyberpunk', 'colorful-green', 'colorful-macaron', 'colorful-memphis', 'colorful-morandi', 'colorful-retro', 'pure-daylight', 'pure-default', 'pure-ember', 'pure-glacier', 'pure-quiet')
        $listed = @(Get-UpwshThemeList)
        Assert-Equal ($listed.Name -join ',') ($expected -join ',')
        Assert-Equal @($listed | Where-Object Active).Count 1
        try {
            foreach ($name in $expected) {
                $file = Join-Path $themes "$name.json"
                $data = [IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable
                Assert-Equal $data.Name $name
                Assert-Equal $data.Version 2
                Assert-True ($data._Comment.Contains('AttachTo')) "missing connector documentation in $name"
                Assert-True ($data._Comment.Contains('Background')) "missing background documentation in $name"
                Assert-Equal (Invoke-ThemeCli @('theme','install',$name)).Code 0
                Assert-Equal (Get-UpwshTheme).Name $name
                $colorful = $name.StartsWith('colorful-')
                $success = if ($colorful) { " $env:USERNAME  $hostName  ~  ❯ " } elseif ($name -eq 'pure-quiet') { '~ > ' } else { "$identity ~ ❯ " }
                $failure = if ($colorful) { " $env:USERNAME  $hostName  ~  2s345ms 7 ❯ " } elseif ($name -eq 'pure-quiet') { '~ 7! ' } else { "$identity ~ 2s345ms7❯ " }
                Assert-Equal (Get-UpwshPromptText -Color Never) $success
                Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 2345 -Color Never) $failure
                $rgb = @(1, 3, 5 | ForEach-Object { [Convert]::ToInt32($data.Modules.directory.Foreground.Substring($_, 2), 16) }) -join ';'
                $attributes = if ($name -eq 'pure-default') { '3;' } else { '' }
                $background = if ($colorful) {
                    '48;2;' + (@(1, 3, 5 | ForEach-Object { [Convert]::ToInt32($data.Modules.directory.Background.Substring($_, 2), 16) }) -join ';')
                } else { '49' }
                $prefix = if ($colorful) { ' ' } else { '' }
                Assert-True ((Get-UpwshPromptText -Color Always).Contains("$([char]27)[0;$($attributes)38;2;$rgb;${background}m$prefix~ ")) "wrong directory style for $name"
                Assert-Equal (Get-UpwshPromptText -DurationMs 1999 -Color Never) $success
            }
        } finally { $null = Set-UpwshTheme 'pure-default' }
    }
    Test-Theme 'colorful presets render all Git, duration and failure combinations' {
        $repo = Join-Path $HOME 'colorful-repo'
        [void][IO.Directory]::CreateDirectory((Join-Path $repo '.git'))
        [IO.File]::WriteAllText((Join-Path $repo '.git\HEAD'), 'ref: refs/heads/dev')
        try {
            foreach ($name in @('colorful-blue', 'colorful-green', 'colorful-macaron', 'colorful-morandi', 'colorful-cyberpunk', 'colorful-retro', 'colorful-memphis')) {
                $null = Set-UpwshTheme $name
                foreach ($inRepo in @($true, $false)) {
                    Push-Location $(if ($inRepo) { $repo } else { $HOME })
                    try {
                        foreach ($success in @($true, $false)) {
                            foreach ($ms in @(0, 2345)) {
                                $expected = " $env:USERNAME  $hostName  "
                                $expected += if ($inRepo) { 'colorful-repo  dev ' } else { '~ ' }
                                if ($ms) { $expected += ' 2s345ms' }
                                if (-not $success) { $expected += ' 7' }
                                $expected += ' ❯ '
                                Assert-Equal (Get-UpwshPromptText -Succeeded $success -ExitCode 7 -DurationMs $ms -Color Never) $expected
                            }
                        }
                    } finally { Pop-Location }
                }
            }
        } finally { $null = Set-UpwshTheme 'pure-default' }
    }
    Test-Theme 'fresh installations do not provide old-name aliases' {
        foreach ($name in @('iWonder', 'Glacier', 'Ember', 'Quiet', 'Daylight', 'blue_iWonder')) {
            Assert-Equal (Invoke-ThemeCli @('theme', 'install', $name)).Code 1
        }
        Assert-Equal (Get-UpwshTheme).Name 'pure-default'
    }
    Test-Theme 'comment metadata is optional and does not affect rendering' {
        $file = Join-Path $themes 'pure-glacier.json'
        $saved = [IO.File]::ReadAllText($file)
        try {
            $null = Set-UpwshTheme 'pure-glacier'
            $before = Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 2345 -Color Always
            $data = $saved | ConvertFrom-Json -AsHashtable
            $data.Remove('_Comment')
            [IO.File]::WriteAllText($file, ($data | ConvertTo-Json -Depth 4))
            $null = Set-UpwshTheme 'pure-glacier'
            Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 2345 -Color Always) $before
        } finally {
            [IO.File]::WriteAllText($file, $saved)
            $null = Set-UpwshTheme 'pure-default'
        }
    }
    Test-Theme 'invalid theme command shapes show usage' {
        $cases = @(
            ,@('theme')
            ,@('theme','install')
            ,@('theme','list','extra')
            ,@('theme','unknown')
        )
        foreach ($tokens in $cases) {
            $result = Invoke-ThemeCli $tokens
            Assert-Equal $result.Code 2
            Assert-True ($result.Text.Contains('upwsh theme')) 'missing theme usage'
        }
        Assert-Equal (Invoke-ThemeCli @('theme','--help')).Code 0
    }
    Test-Theme 'selecting pure-default persists only a local filename reference' {
        $result = Invoke-ThemeCli @('theme','install','pure-default')
        Assert-Equal $result.Code 0
        Assert-Equal (([IO.File]::ReadAllText($selection) | ConvertFrom-Json).Theme) 'pure-default.json'
    }

    $alternate = [IO.File]::ReadAllText((Join-Path $themes 'pure-default.json')) | ConvertFrom-Json -AsHashtable
    $alternate.Name = 'Quiet Blue'
    $alternate.Modules.directory.Foreground = '#123456'
    $alternate.Modules.symbol.Text = '$'
    $alternate.Modules.symbol.Failure.Text = '!'
    foreach ($id in @('user', 'host', 'git', 'duration', 'exitCode')) { $alternate.Modules[$id].Enabled = $false }
    $alternate.Modules.directory.Style = 'path'
    $alternate.Modules.directory.Italic = $false
    $alternate.Modules.symbol.Bold = $false
    $alternatePath = Join-Path $themes 'Quiet Blue.json'
    [IO.File]::WriteAllText($alternatePath, ($alternate | ConvertTo-Json -Depth 4))

    Test-Theme 'theme install refreshes current prompt without reloading modules' {
        $beforeModule = Get-Module hook
        $null = Get-RenderedPrompt
        $result = Invoke-ThemeCli @('theme','install','Quiet Blue')
        Assert-Equal $result.Code 0
        Assert-Equal (Get-RenderedPrompt) '~ $ '
        Assert-True ([object]::ReferenceEquals($beforeModule, (Get-Module hook))) 'switch reloaded the runtime'
        Assert-Equal (Get-UpwshPromptText -Succeeded $false -ExitCode 7 -DurationMs 5000 -Color Never) '~ ! '
        Assert-True ((Get-UpwshPromptText -Color Always).Contains("$([char]27)[0;38;2;18;52;86;49m~ ")) 'theme RGB was not used'
        $directory = Join-Path $HOME 'nested\directory'
        [void][IO.Directory]::CreateDirectory($directory)
        Push-Location $directory
        try { Assert-Equal (Get-UpwshPromptText -Color Never) '~/nested/directory $ ' } finally { Pop-Location }
        Assert-True ((Invoke-ThemeCli @('theme','list')).Text.Contains('* Quiet Blue')) 'active marker did not move'
    }
    Test-Theme 'unknown or invalid themes do not replace the active selection' {
        $before = [IO.File]::ReadAllText($selection)
        [IO.File]::WriteAllText((Join-Path $themes 'Broken.json'), '{"Name":"Broken","Version":2}')
        foreach ($name in @('missing', 'Broken', '../pure-default', 'C:\pure-default', 'pure-default.json')) {
            $result = Invoke-ThemeCli @('theme','install',$name)
            Assert-Equal $result.Code 1
            Assert-Equal ([IO.File]::ReadAllText($selection)) $before
        }
        Assert-Equal (Get-RenderedPrompt) '~ $ '
    }
    Test-Theme 'schema validation rejects unsafe or wrongly typed settings before switching' {
        $badPath = Join-Path $themes 'Invalid.json'
        $before = [IO.File]::ReadAllText($selection)
        $mutations = @(
            { param($data) $data.Modules.directory.Foreground = 'red' }
            { param($data) $data.Modules.directory.Background = '#12345678' }
            { param($data) $data.Modules.directory.Background = 'previous.background' }
            { param($data) $data.Modules.symbol.Text = "$([char]27)]2;injected$([char]7)" }
            { param($data) $data.Modules.symbol.Failure.Background = 'red' }
            { param($data) $data.Modules.directory.Prefix = "bad`nline" }
            { param($data) $data.Modules.git.Enabled = 'true' }
            { param($data) $data.Modules.duration.MinMs = -1 }
            { param($data) $data.Modules.directory.Style = @('folder') }
            { param($data) $data.Modules.at.AttachTo = @('at') }
            { param($data) $data.Modules.at.AttachTo = 'user' }
            { param($data) $data.Modules.at.When = 'sometimes' }
            { param($data) $data.Modules.at.Command = 'whoami' }
            { param($data) $data.Modules.at.Type = 'script' }
            { param($data) $data.Modules.at.Type = @('text') }
            { param($data) $data.Modules.at.Type = @() }
            { param($data) $data.Order = @('missing') }
            { param($data) $data.Order = @('User') }
            { param($data) $data.Order = 'user' }
            { param($data) $data.Modules.directory.Forground = '#123456' }
            { param($data) $data.Version = 1 }
            { param($data) $data.Version = '2' }
        )
        foreach ($mutate in $mutations) {
            $bad = [IO.File]::ReadAllText((Join-Path $themes 'pure-default.json')) | ConvertFrom-Json -AsHashtable
            $bad.Name = 'Invalid'
            & $mutate $bad
            [IO.File]::WriteAllText($badPath, ($bad | ConvertTo-Json -Depth 4))
            Assert-Equal (Invoke-ThemeCli @('theme','install','Invalid')).Code 1
            Assert-Equal ([IO.File]::ReadAllText($selection)) $before
        }
        [IO.File]::WriteAllText($badPath, 'not json')
        Assert-Equal (Invoke-ThemeCli @('theme','install','Invalid')).Code 1
        Assert-Equal ([IO.File]::ReadAllText($selection)) $before
        $listed = @(Get-UpwshThemeList -WarningAction SilentlyContinue)
        Assert-True ('Invalid' -notin $listed.Name -and 'Broken' -notin $listed.Name) 'invalid theme was listed'
    }
    Test-Theme 'a theme hiding Git does not query it to render' {
        $module = (Get-Command Get-UpwshPromptText).Module
        $saved = & $module { (Get-Command Get-PromptGitBranch).ScriptBlock }
        try {
            & $module { Set-Item Function:Get-PromptGitBranch { throw 'theme hid Git but still queried it' } }
            Assert-Equal (Get-UpwshPromptText -Color Never) '~ $ '
        } finally { & $module { param($body) Set-Item Function:Get-PromptGitBranch $body } $saved }
    }
    Test-Theme 'theme selection from -File is picked up on the next parent prompt' {
        $result = Invoke-UpwshTestProcess -UserHome $HOME -File $entry -Arguments @('theme','install','pure-default')
        Assert-Equal $result.Code 0
        Assert-Equal (Get-RenderedPrompt) "$identity ~ ❯ "
    }
    Test-Theme 'new pwsh loads the selected theme' {
        $result = Invoke-ThemeCli @('theme','install','Quiet Blue')
        Assert-Equal $result.Code 0
        $command = '. ' + (ConvertTo-TestLiteral (Join-Path $installHome 'profile.ps1')) + '; Get-UpwshPromptText -Color Never'
        $child = Invoke-UpwshTestProcess -UserHome $HOME -Command $command
        Assert-Equal $child.Code 0
        Assert-Equal $child.Text.TrimEnd("`r", "`n") '~ $ '
    }
    Test-Theme 'selecting the same edited theme explicitly reloads its data' {
        $alternate.Modules.symbol.Text = '»'
        [IO.File]::WriteAllText($alternatePath, ($alternate | ConvertTo-Json -Depth 4))
        Assert-Equal (Invoke-ThemeCli @('theme','install','Quiet Blue')).Code 0
        Assert-Equal (Get-RenderedPrompt) '~ » '
    }
    Test-Theme 'malformed reference is recoverable without breaking an existing prompt' {
        [IO.File]::WriteAllText($selection, 'not json')
        $warnings = @()
        $theme = Get-UpwshTheme -Reload -WarningVariable warnings -WarningAction SilentlyContinue
        Assert-Equal $theme.Name 'Quiet Blue'
        Assert-True ($warnings.Count -gt 0) 'invalid reference was silent'
        Assert-Equal (Invoke-ThemeCli @('theme','install','pure-default')).Code 0
        Assert-Equal (Get-RenderedPrompt) "$identity ~ ❯ "
    }
    Test-Theme 'a malformed reference in a fresh shell falls back to pure-default' {
        $saved = [IO.File]::ReadAllText($selection)
        try {
            [IO.File]::WriteAllText($selection, '{"Theme":"../../escape.json"}')
            $command = '. ' + (ConvertTo-TestLiteral (Join-Path $installHome 'profile.ps1')) + '; $WarningPreference = "SilentlyContinue"; Get-UpwshPromptText -Color Never'
            $child = Invoke-UpwshTestProcess -UserHome $HOME -Command $command
            Assert-Equal $child.Code 0
            Assert-Equal $child.Text.TrimEnd("`r", "`n") "$identity ~ ❯ "
        } finally { [IO.File]::WriteAllText($selection, $saved) }
    }
    Test-Theme 'update adds missing bundled themes while preserving theme selection and local files' {
        Assert-Equal (Invoke-ThemeCli @('theme','install','Quiet Blue')).Code 0
        $before = [IO.File]::ReadAllText($alternatePath)
        $beforeSelection = [IO.File]::ReadAllText($selection)
        $installedDefault = Join-Path $themes 'pure-default.json'
        $default = [IO.File]::ReadAllText($installedDefault) | ConvertFrom-Json -AsHashtable
        $default.Modules.symbol.Foreground = '#102030'
        [IO.File]::WriteAllText($installedDefault, ($default | ConvertTo-Json -Depth 4))
        $beforeDefault = [IO.File]::ReadAllText($installedDefault)
        $missing = @('pure-glacier', 'pure-ember', 'pure-quiet', 'pure-daylight', 'colorful-blue', 'colorful-cyberpunk', 'colorful-green', 'colorful-macaron', 'colorful-memphis', 'colorful-morandi', 'colorful-retro')
        foreach ($name in $missing) {
            [IO.File]::Delete((Join-Path $themes "$name.json"))
        }
        $result = Invoke-UpwshTestProcess -UserHome $HOME -File (Join-Path $runtime 'scripts\update.ps1') -Arguments @('--source', $runtime)
        Assert-True ($result.Code -eq 0) $result.Text
        foreach ($name in $missing) {
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $themes "$name.json"))) ([IO.File]::ReadAllText((Join-Path $runtime "themes\$name.json")))
        }
        Assert-Equal ([IO.File]::ReadAllText($selection)) $beforeSelection
        Assert-Equal ([IO.File]::ReadAllText($alternatePath)) $before
        Assert-Equal ([IO.File]::ReadAllText($installedDefault)) $beforeDefault
        Assert-Equal (Get-RenderedPrompt) '~ » '
    }
    Test-Theme 'updating over an old bundled theme fails before changing runtime or user files' {
        $file = Join-Path $themes 'pure-default.json'
        $saved = [IO.File]::ReadAllText($file)
        $promptPath = Join-Path $installHome 'prompt.psm1'
        $beforePrompt = [IO.File]::ReadAllText($promptPath)
        $beforeSelection = [IO.File]::ReadAllText($selection)
        try {
            [IO.File]::WriteAllText($file, '{"Version":1,"Name":"pure-default"}')
            $result = Invoke-UpwshTestProcess -UserHome $HOME -File (Join-Path $runtime 'scripts\update.ps1') -Arguments @('--source', $runtime)
            Assert-Equal $result.Code 1
            Assert-True ($result.Text.Contains('Version 2')) $result.Text
            Assert-True ($result.Text.Contains('Back up')) $result.Text
            Assert-Equal ([IO.File]::ReadAllText($promptPath)) $beforePrompt
            Assert-Equal ([IO.File]::ReadAllText($selection)) $beforeSelection
            Assert-Equal ([IO.File]::ReadAllText($file)) '{"Version":1,"Name":"pure-default"}'
        } finally { [IO.File]::WriteAllText($file, $saved) }
    }
} finally { Pop-Location }
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) theme tests failed."
}
Write-Output "$script:Passed theme tests passed."
