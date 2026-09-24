$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    $testUserHome = Join-Path ([IO.Path]::GetTempPath()) ("upwsh path user's " + [guid]::NewGuid().ToString('N'))
    try {
        $result = Invoke-UpwshTestProcess -UserHome $testUserHome -File $PSCommandPath
        Write-Output $result.Text
        exit $result.Code
    } finally {
        Remove-Item -LiteralPath $testUserHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}
. (Join-Path $PSScriptRoot '..\src\profile.ps1')
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++ } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}

Test-Case 'standalone converter copies match the shared implementation' {
    & (Join-Path $PSScriptRoot '..\src\script\sync_path_convert.ps1') -Check | Out-Null
}
foreach ($entry in @('lib\path_convert.ps1', 'lib\upwsh_home.ps1', 'script\install.ps1', 'script\uninstall.ps1')) {
    Test-Case "shared converter contract without a loaded profile: $entry" {
        $file = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\src\$entry"))
        $code = @'
$ErrorActionPreference = 'Stop'
. ENTRY --help | Out-Null
if ((winpath '/c/my work') -cne 'C:/my work') { throw 'drive conversion failed' }
if ((unixpath 'C:\my work') -cne '/c/my work') { throw 'inverse conversion failed' }
if ((winpath 'text /c/a') -cne 'text /c/a') { throw 'literal text changed' }
if ((winpath '~/my work') -cne ($HOME.Replace('\', '/') + '/my work')) { throw 'home expansion failed' }
if ((unixpath 'C:relative') -cne 'C:relative') { throw 'drive-relative path changed' }
if (((@('/c/a', '/d/b') | winpath) -join '|') -cne 'C:/a|D:/b') { throw 'pipeline conversion failed' }
if (Get-Command Set-HookPromptInput -ErrorAction SilentlyContinue) { throw 'converter loaded the interactive shell' }
'@
        $result = Invoke-UpwshTestProcess -UserHome $HOME -Command $code.Replace('ENTRY', (ConvertTo-TestLiteral $file))
        if ($result.Code -ne 0) { throw $result.Text }
    }
}

Test-Case 'winpath converts drive paths including spaces without requiring existence' {
    Assert-Equal (winpath '/c/my work/missing.txt') 'C:/my work/missing.txt'
    Assert-Equal (winpath '/d') 'D:/'
    Assert-Equal (winpath '/e/') 'E:/'
}
Test-Case 'winpath expands home and keeps Windows paths' {
    Assert-Equal (winpath '~/my work') ($HOME.Replace('\', '/').TrimEnd('/') + '/my work')
    Assert-Equal (winpath 'C:\my work') 'C:\my work'
    Assert-Equal (winpath 'C:relative') 'C:relative'
}
Test-Case 'unixpath converts drive paths and UNC paths' {
    Assert-Equal (unixpath 'C:\my work\missing.txt') '/c/my work/missing.txt'
    Assert-Equal (unixpath 'D:\') '/d/'
    Assert-Equal (unixpath '\\server\share\my work') '//server/share/my work'
    Assert-Equal (unixpath 'C:relative') 'C:relative'
}
Test-Case 'multiple paths and pipeline input preserve order' {
    Assert-Equal ((winpath /c/a /d/b) -join '|') 'C:/a|D:/b'
    Assert-Equal ((@('C:\a', 'D:\b') | unixpath) -join '|') '/c/a|/d/b'
    Assert-Equal ((@('/c/a', '/d/b') | winpath) -join '|') 'C:/a|D:/b'
}
Test-Case 'explicit converters preserve empty paths and round-trip UNC and absolute paths' {
    Assert-Equal (winpath '') ''
    Assert-Equal (unixpath '') ''
    Assert-Equal (winpath (unixpath 'C:\my work\a.txt')) 'C:/my work/a.txt'
    Assert-Equal (winpath '//server/share/a') '//server/share/a'
    Assert-Equal (unixpath (winpath '/c/my work')) '/c/my work'
}
Test-Case 'explicit conversion does not replace fragments or expand wildcards' {
    Assert-Equal (winpath 'text /c/a') 'text /c/a'
    Assert-Equal (winpath 'https://example.test/c/a') 'https://example.test/c/a'
    Assert-Equal (winpath '/c/*.txt') 'C:/*.txt'
    Assert-Equal (unixpath 'text C:\a') 'text C:/a'
    Assert-Equal (unixpath 'relative\a') 'relative/a'
    Assert-Equal (unixpath '/c/a') '/c/a'
}

$cases = @(
    ,@('drive argument', 'capture /c/work', 'capture C:/work')
    ,@('unknown command needs no adapter', 'unknown-command /d/work', 'unknown-command D:/work')
    ,@('quoted literal', "capture '/c/work'", "capture '/c/work'")
    ,@('double quoted literal', 'capture "~/work"', 'capture "~/work"')
    ,@('literal substring', "capture 'use /c/demo'", "capture 'use /c/demo'")
    ,@('option value', 'capture --output=/c/a', 'capture --output=/c/a')
    ,@('parameter value', 'capture -Path:/c/a', 'capture -Path:/c/a')
    ,@('regex text', "capture '/c/users' README.md", "capture '/c/users' README.md")
    ,@('script text', "capture -Command 'Write-Output /c/demo'", "capture -Command 'Write-Output /c/demo'")
    ,@('script block', 'capture { capture /c/a } /d/out', 'capture { capture /c/a } D:/out')
    ,@('subexpression', 'capture $(capture /c/a) /d/out', 'capture $(capture /c/a) D:/out')
    ,@('explicit conversion', "capture (winpath '/c/my work')", "capture (winpath '/c/my work')")
    ,@('comment', 'capture /c/a # /d/comment', 'capture C:/a # /d/comment')
    ,@('compound tokens', "capture /c/a; capture '/d/literal' /e/b", "capture C:/a; capture '/d/literal' E:/b")
    ,@('pipeline tokens', 'capture /c/a | capture /d/b', 'capture C:/a | capture D:/b')
    ,@('pipeline chain tokens', 'capture /c/a && capture /d/b', 'capture C:/a && capture D:/b')
    ,@('assignment body', '$text = capture /c/a', '$text = capture /c/a')
    ,@('conditional body', 'if ($true) { capture /c/a }', 'if ($true) { capture /c/a }')
    ,@('variable expression', 'capture /c/$name', 'capture /c/$name')
    ,@('escaped whitespace', 'capture /c/my` work', 'capture /c/my` work')
    ,@('quoted segment', 'capture /c/"my work"', 'capture /c/"my work"')
    ,@('stop parsing', 'capture --% /c/a', 'capture --% /c/a')
    ,@('redirection', 'capture /c/a > /d/out', 'capture C:/a > /d/out')
    ,@('function definition', 'function f { capture /c/a }', 'function f { capture /c/a }')
    ,@('incomplete input', "capture /c/a '", "capture /c/a '")
    ,@('glob argument', 'capture /c/*.txt', "capture 'C:/*.txt'")
    ,@('relative argument', 'capture ./foo ../bar feature/name', 'capture ./foo ../bar feature/name')
    ,@('here string', "capture @'`n/c/data`n'@", "capture @'`n/c/data`n'@")
)
foreach ($case in $cases) {
    Test-Case $case[0] { Assert-Equal (ConvertTo-WindowsCommandLine $case[1]) $case[2] }
}
Test-Case 'home paths are emitted as one literal argument when HOME contains spaces' {
    $expected = 'capture ' + (ConvertTo-QuotedText ($HOME.Replace('\', '/') + '/my-file'))
    Assert-Equal (ConvertTo-WindowsCommandLine 'capture ~/my-file') $expected
}
Test-Case 'functions and cmdlets use the same argument rewriting' {
    function capture { $args }
    $line = ConvertTo-WindowsCommandLine "capture /c/a '/d/text' (winpath '/e/my work')"
    Assert-Equal ((Invoke-Expression $line) -join '|') 'C:/a|/d/text|E:/my work'
}
Test-Case 'native applications receive converted bare arguments and unchanged literals' {
    $receiver = Join-Path $HOME 'receive arguments.ps1'
    [IO.File]::WriteAllText($receiver, 'ConvertTo-Json -InputObject @($args) -Compress')
    $pwsh = (Get-Process -Id $PID).Path
    $line = '& ' + (ConvertTo-TestLiteral $pwsh) + ' -NoLogo -NoProfile -File ' + (ConvertTo-TestLiteral $receiver) + " /c/a '/d/literal' (winpath '/e/my work')"
    $received = Invoke-Expression (ConvertTo-WindowsCommandLine $line) | ConvertFrom-Json
    Assert-Equal ($received -join '|') 'C:/a|/d/literal|E:/my work'
}
Test-Case 'unsafe converted paths are quoted to prevent PowerShell interpretation' {
    function capture { $args }
    $line = ConvertTo-WindowsCommandLine 'capture /c/[draft].txt'
    Assert-Equal (Invoke-Expression $line) 'C:/[draft].txt'
}
Test-Case 'relative and quoted arguments remain untouched by filesystem operand helpers' {
    Assert-Equal ((ConvertTo-WindowsPathOperands @('/c/no-such-test-item')) -join '|') '/c/no-such-test-item'
    Assert-Equal ((ConvertTo-WindowsPathOperands @('text /c/a')) -join '|') 'text /c/a'
}
Test-Case 'absolute completion containing spaces is executable' {
    $directory = Join-Path $HOME 'my work'
    [void][IO.Directory]::CreateDirectory($directory)
    $prefix = (unixpath $HOME) + '/my'
    $line = 'capture ' + (ConvertTo-QuotedText $prefix)
    $state = Complete-HookLine -Line $line
    $text = $line.Substring($state.ReplacementIndex, $state.ReplacementLength)
    $decision = Get-CompletionDecision -Matches $state.Matches -CurrentText $text
    $completed = $line.Remove($state.ReplacementIndex, $state.ReplacementLength).Insert($state.ReplacementIndex, $decision.Replacement)
    function capture { $args }
    Assert-Equal (Invoke-Expression (ConvertTo-WindowsCommandLine $completed)) ($directory.Replace('\','/') + '/')
    if (-not $completed.Contains('(winpath ')) { throw 'completion missed explicit conversion' }
}
Test-Case 'attached option completion produces a usable path without Enter rewriting' {
    $match = [Management.Automation.CompletionResult]::new("--output='C:\my work'", 'my work', 'ProviderContainer', 'C:\my work')
    $normalized = ConvertTo-UnixCompletionResult -Match $match -CurrentText '--output=C:/my'
    function capture { $args }
    Assert-Equal (Invoke-Expression ('capture ' + $normalized.CompletionText)) '--output=C:/my work/'
}
Test-Case 'repeated Tab inside generated winpath completion stays executable' {
    $line = "capture (winpath '~/my work/')"
    $child = Join-Path $HOME 'my work\child.txt'
    [IO.File]::WriteAllText($child, '')
    $cursor = $line.IndexOf("')")
    $state = Complete-HookLine -Line $line -Cursor $cursor
    $text = $line.Substring($state.ReplacementIndex, $state.ReplacementLength)
    $decision = Get-CompletionDecision -Matches $state.Matches -CurrentText $text -LiteralPaths:$state.LiteralPaths
    $completed = $line.Remove($state.ReplacementIndex, $state.ReplacementLength).Insert($state.ReplacementIndex, $decision.Replacement)
    function capture { $args }
    Assert-Equal (Invoke-Expression (ConvertTo-WindowsCommandLine $completed)) $child.Replace('\','/')
}
Test-Case 'completion within explicit conversion keeps the literal path argument' {
    $line = "capture (winpath '~/my')"
    $cursor = $line.IndexOf("')")
    $state = Complete-HookLine -Line $line -Cursor $cursor
    $text = $line.Substring($state.ReplacementIndex, $state.ReplacementLength)
    $decision = Get-CompletionDecision -Matches $state.Matches -CurrentText $text -LiteralPaths:$state.LiteralPaths
    Assert-Equal $decision.Replacement "'~/my work/'"
}
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) path command tests failed."
}
Write-Output "$script:Passed path command tests passed."
