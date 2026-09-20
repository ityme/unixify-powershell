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
    Test-Theme 'default theme list marks iWonder active without creating a selection' {
        $result = Invoke-ThemeCli @('theme','list')
        Assert-Equal $result.Code 0
        Assert-True ($result.Text.Contains('* iWonder')) $result.Text
        Assert-True (-not [IO.File]::Exists($selection)) 'list wrote selection'
        Assert-Equal (Get-UpwshPromptText -Color Never) "$identity ~ ❯ "
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
    Test-Theme 'selecting iWonder persists only a local filename reference' {
        $result = Invoke-ThemeCli @('theme','install','iWonder')
        Assert-Equal $result.Code 0
        Assert-Equal (([IO.File]::ReadAllText($selection) | ConvertFrom-Json).Theme) 'iWonder.json'
    }

    $alternate = [IO.File]::ReadAllText((Join-Path $themes 'iWonder.json')) | ConvertFrom-Json -AsHashtable
    $alternate.Name = 'Quiet Blue'
    $alternate.Colors.Directory = '#123456'
    $alternate.Symbols.Success = '$'
    $alternate.Symbols.Error = '!'
    $alternate.Display.ShowUserHost = $false
    $alternate.Display.ShowGitBranch = $false
    $alternate.Display.ShowDuration = $false
    $alternate.Display.ShowExitCode = $false
    $alternate.Display.DirectoryStyle = 'path'
    $alternate.Display.DirectoryItalic = $false
    $alternate.Display.SymbolBold = $false
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
        Assert-True ((Get-UpwshPromptText -Color Always).Contains("$([char]27)[38;2;18;52;86m~ ")) 'theme RGB was not used'
        $directory = Join-Path $HOME 'nested\directory'
        [void][IO.Directory]::CreateDirectory($directory)
        Push-Location $directory
        try { Assert-Equal (Get-UpwshPromptText -Color Never) '~/nested/directory $ ' } finally { Pop-Location }
        Assert-True ((Invoke-ThemeCli @('theme','list')).Text.Contains('* Quiet Blue')) 'active marker did not move'
    }
    Test-Theme 'unknown or invalid themes do not replace the active selection' {
        $before = [IO.File]::ReadAllText($selection)
        [IO.File]::WriteAllText((Join-Path $themes 'Broken.json'), '{"Name":"Broken","Version":1}')
        foreach ($name in @('missing', 'Broken', '../iWonder', 'C:\iWonder', 'iWonder.json')) {
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
            { param($data) $data.Colors.Directory = 'red' }
            { param($data) $data.Symbols.Success = "$([char]27)]2;injected$([char]7)" }
            { param($data) $data.Display.ShowGitBranch = 'true' }
            { param($data) $data.Display.DurationMinMs = -1 }
            { param($data) $data.Display.DirectoryStyle = @('folder') }
            { param($data) $data.Version = '1' }
        )
        foreach ($mutate in $mutations) {
            $bad = [IO.File]::ReadAllText((Join-Path $themes 'iWonder.json')) | ConvertFrom-Json -AsHashtable
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
        $result = Invoke-UpwshTestProcess -UserHome $HOME -File $entry -Arguments @('theme','install','iWonder')
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
        $alternate.Symbols.Success = '»'
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
        Assert-Equal (Invoke-ThemeCli @('theme','install','iWonder')).Code 0
        Assert-Equal (Get-RenderedPrompt) "$identity ~ ❯ "
    }
    Test-Theme 'a malformed reference in a fresh shell falls back to iWonder' {
        $saved = [IO.File]::ReadAllText($selection)
        try {
            [IO.File]::WriteAllText($selection, '{"Theme":"../../escape.json"}')
            $command = '. ' + (ConvertTo-TestLiteral (Join-Path $installHome 'profile.ps1')) + '; $WarningPreference = "SilentlyContinue"; Get-UpwshPromptText -Color Never'
            $child = Invoke-UpwshTestProcess -UserHome $HOME -Command $command
            Assert-Equal $child.Code 0
            Assert-Equal $child.Text.TrimEnd("`r", "`n") "$identity ~ ❯ "
        } finally { [IO.File]::WriteAllText($selection, $saved) }
    }
    Test-Theme 'update preserves theme selection and local theme files' {
        Assert-Equal (Invoke-ThemeCli @('theme','install','Quiet Blue')).Code 0
        $before = [IO.File]::ReadAllText($alternatePath)
        $beforeSelection = [IO.File]::ReadAllText($selection)
        $installedDefault = Join-Path $themes 'iWonder.json'
        $default = [IO.File]::ReadAllText($installedDefault) | ConvertFrom-Json -AsHashtable
        $default.Colors.Success = '#102030'
        [IO.File]::WriteAllText($installedDefault, ($default | ConvertTo-Json -Depth 4))
        $beforeDefault = [IO.File]::ReadAllText($installedDefault)
        $result = Invoke-UpwshTestProcess -UserHome $HOME -File (Join-Path $runtime 'scripts\update.ps1') -Arguments @('--source', $runtime)
        Assert-True ($result.Code -eq 0) $result.Text
        Assert-Equal ([IO.File]::ReadAllText($selection)) $beforeSelection
        Assert-Equal ([IO.File]::ReadAllText($alternatePath)) $before
        Assert-Equal ([IO.File]::ReadAllText($installedDefault)) $beforeDefault
        Assert-Equal (Get-RenderedPrompt) '~ » '
    }
} finally { Pop-Location }
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) theme tests failed."
}
Write-Output "$script:Passed theme tests passed."
