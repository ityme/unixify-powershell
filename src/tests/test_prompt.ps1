$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot '..\profile.ps1')
$hook = (Get-Command prompt).Module
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected <$Expected>, got <$Actual>" }
}
function Invoke-PromptTest {
    param([string]$Name, [scriptblock]$Body)
    try {
        $global:PromptRenderCount = 0
        & $hook {
            $script:CachedPrompt = $null
            $script:CommandPending = $false
            $script:SubmittedParseError = $false
            $script:LastCommandSucceeded = $true
            $script:LastCommandExitCode = 0
            $script:ReadingInput = $false
            $script:BasePrompt = { $global:PromptRenderCount++; "render:$global:PromptRenderCount> " }
        }
        & $Body
        $script:Passed++
    } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Capture-Prompt {
    $writer = [IO.StringWriter]::new()
    $original = [Console]::Out
    try {
        [Console]::SetOut($writer)
        $text = prompt
        [pscustomobject]@{ Text = $text; Report = $writer.ToString() }
    } finally { [Console]::SetOut($original); $writer.Dispose() }
}
$originalOut = [Console]::Out
try {
    [Console]::SetOut([IO.TextWriter]::Null)
    Invoke-PromptTest 'first prompt renders once and repeated idle requests reuse it' {
        Assert-Equal (prompt) 'render:1> '
        Assert-Equal (prompt) 'render:1> '
        Assert-Equal (prompt) 'render:1> '
    }
    Invoke-PromptTest 'empty whitespace and comment-only submissions do not rerender' {
        $null = prompt
        foreach ($line in @('', " `t ", '# comment', "<# block comment`ncontinues #>", "# first`n# second")) {
            Set-HookPromptInput -Line $line
            Assert-Equal (prompt) 'render:1> '
        }
    }
    Invoke-PromptTest 'a submitted statement renders once even if the directory is unchanged' {
        $null = prompt
        foreach ($line in @('$x = 1', 'Write-Output value', 'while ($false) { }')) {
            $before = $global:PromptRenderCount
            Set-HookPromptInput -Line $line
            $null = prompt
            $null = prompt
            Assert-Equal $global:PromptRenderCount ($before + 1)
        }
    }
    Invoke-PromptTest 'submitted syntax errors refresh but incomplete editing does not start a command' {
        $null = prompt
        Set-HookPromptInput -Line 'Write-Output "unfinished'
        Assert-Equal (prompt) 'render:1> '
        Set-HookPromptInput -Line '1 + * 2'
        Assert-Equal (prompt) 'render:2> '
    }
    Invoke-PromptTest 'input editing redraws emit no command or prompt events' {
        $null = prompt
        & $hook { $script:ReadingInput = $true }
        try {
            foreach ($i in 1..3) {
                $result = Capture-Prompt
                Assert-Equal $result.Text 'render:1> '
                Assert-Equal $result.Report ''
            }
        } finally { & $hook { $script:ReadingInput = $false } }
    }
    Invoke-PromptTest 'idle new prompts report boundaries without a command-finished marker' {
        $null = prompt
        $result = Capture-Prompt
        Assert-Equal $result.Text 'render:1> '
        if (-not $result.Report.Contains(']133;A') -or -not $result.Report.Contains(']133;B')) { throw 'prompt boundary missing' }
        if ($result.Report.Contains(']133;D;')) { throw 'idle prompt claimed a command completed' }
    }
    Invoke-PromptTest 'command completion reports once and leaves the cache clean' {
        $null = prompt
        Set-HookPromptInput -Line '$null = 1'
        $completed = Capture-Prompt
        Assert-Equal $completed.Text 'render:2> '
        if (-not $completed.Report.Contains(']133;D;0')) { throw 'command completion missing' }
        $idle = Capture-Prompt
        Assert-Equal $idle.Text 'render:2> '
        if ($idle.Report.Contains(']133;D;')) { throw 'command completion repeated' }
    }
    Invoke-PromptTest 'pending command status survives redraw and is consumed after input returns' {
        $null = prompt
        Set-HookPromptInput -Line 'example-command'
        & $hook { $script:ReadingInput = $true }
        try { Assert-Equal (Capture-Prompt).Report '' }
        finally { & $hook { $script:ReadingInput = $false } }
        $null = Capture-Prompt
        Assert-Equal (& $hook { $script:CommandPending }) $false
    }
    Invoke-PromptTest 'location and width invalidate rendering without a command' {
        $null = prompt
        $directory = Join-Path $HOME 'new-directory'
        [void][IO.Directory]::CreateDirectory($directory)
        Push-Location $directory
        try {
            Assert-Equal (prompt) 'render:2> '
            Assert-Equal (prompt) 'render:2> '
        } finally { Pop-Location }
        $null = prompt
        $before = $global:PromptRenderCount
        & $hook { $script:CachedPromptWidth = -1 }
        Assert-Equal (prompt) "render:$($before + 1)> "
    }
    Invoke-PromptTest 'candidate display follows the same no-command rendering policy' {
        $null = prompt
        & $hook { $script:CompletionDisplayState = [pscustomobject]@{ Line = 'git pull origin ' }; $script:ReadingInput = $true }
        try {
            Assert-Equal (Capture-Prompt).Report ''
            Assert-Equal (prompt) 'render:1> '
            & $hook { $script:CachedPromptWidth = -1 }
            $result = Capture-Prompt
            Assert-Equal $result.Text 'render:2> '
            Assert-Equal $result.Report ''
        } finally { & $hook { $script:CompletionDisplayState = $null; $script:ReadingInput = $false } }
    }
    Invoke-PromptTest 'native exit code survives fresh render and repeated redraw' {
        $global:LASTEXITCODE = 7
        Set-HookPromptInput -Line 'example-command'
        $null = prompt
        Assert-Equal $global:LASTEXITCODE 7
        $null = prompt
        Assert-Equal $global:LASTEXITCODE 7
        $global:LASTEXITCODE = 0
    }
    Invoke-PromptTest 'external state stays a snapshot until a command is submitted' {
        & $hook {
            $script:ExternalSnapshotFixture = 'before'
            $script:BasePrompt = { $script:ExternalSnapshotFixture }
        }
        Assert-Equal (prompt) 'before'
        & $hook { $script:ExternalSnapshotFixture = 'after' }
        Set-HookPromptInput -Line ''
        Assert-Equal (prompt) 'before'
        Set-HookPromptInput -Line '# comment'
        Assert-Equal (prompt) 'before'
        Set-HookPromptInput -Line 'git status'
        Assert-Equal (prompt) 'after'
    }
    Invoke-PromptTest 'failure snapshot reaches the renderer without adding synthetic errors' {
        & $hook { $script:BasePrompt = { [string]$global:? } }
        Set-HookPromptInput -Line 'example-command'
        $errorCount = $Error.Count
        $global:LASTEXITCODE = 7
        Write-Error 'controlled failure' -ErrorAction Ignore
        $rendered = prompt
        Assert-Equal $rendered 'False'
        Assert-Equal $global:LASTEXITCODE 7
        Assert-Equal $Error.Count $errorCount
        Assert-Equal (prompt) 'False'
        Set-HookPromptInput -Line '$null = 1'
        Assert-Equal (prompt) 'True'
        $global:LASTEXITCODE = 0
    }
    Invoke-PromptTest 'command duration is captured before a slow renderer' {
        $null = prompt
        & $hook { $script:BasePrompt = { Start-Sleep -Milliseconds 250; 'slow> ' } }
        Set-HookPromptInput -Line '$null = 1'
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Capture-Prompt
        $watch.Stop()
        $encoded = [regex]::Match($result.Report, 'SetUserVar=ELAPSED_MS=([^\x07]*)').Groups[1].Value
        $duration = [int][Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
        if ($duration -ge ($watch.Elapsed.TotalMilliseconds - 150)) { throw "renderer included in command duration: $duration ms" }
    }
} finally {
    [Console]::SetOut($originalOut)
    Remove-Variable PromptRenderCount -Scope Global -ErrorAction SilentlyContinue
}
if ($script:Failures.Count) {
    $script:Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "$($script:Failures.Count) prompt tests failed."
}
Write-Output "$script:Passed prompt tests passed."
