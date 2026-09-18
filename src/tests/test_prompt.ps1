$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_test_host.ps1')
if ($env:UPWSH_TEST_ISOLATED -ne '1') {
    Invoke-UpwshIsolatedTest -File $PSCommandPath
    exit $LASTEXITCODE
}

. (Join-Path $PSScriptRoot '..\profile.ps1')
$script:Passed = 0
$script:Failures = [Collections.Generic.List[string]]::new()
function Invoke-PromptTest {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++ } catch { $script:Failures.Add("$Name`: $($_.Exception.Message)") }
}
function Assert-Equal {
    param($Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) { throw "expected '$Expected', got '$Actual'" }
}

$hook = (Get-Command prompt).Module
$originalOut = [Console]::Out
$global:PromptRenderCount = 0
try {
    [Console]::SetOut([IO.TextWriter]::Null)
    & $hook {
        $script:BasePrompt = {
            $global:PromptRenderCount++
            "render:$global:PromptRenderCount> "
        }
    }
    Invoke-PromptTest 'first prompt renders normally' {
        Assert-Equal (prompt) 'render:1> '
        Assert-Equal $global:PromptRenderCount 1
    }
    Invoke-PromptTest 'empty Enter reuses the prompt without running its renderer' {
        Set-HookPromptInput -Line ''
        Assert-Equal (prompt) 'render:1> '
        Assert-Equal $global:PromptRenderCount 1
    }
    Invoke-PromptTest 'whitespace Enter also reuses the prompt' {
        Set-HookPromptInput -Line " `t "
        Assert-Equal (prompt) 'render:1> '
    }
    Invoke-PromptTest 'a real command refreshes once even with the same directory' {
        Set-HookPromptInput -Line 'git status'
        Assert-Equal (prompt) 'render:2> '
        Set-HookPromptInput -Line ''
        Assert-Equal (prompt) 'render:2> '
        Assert-Equal $global:PromptRenderCount 2
    }
    Invoke-PromptTest 'a prompt without an empty Enter event refreshes' {
        Assert-Equal (prompt) 'render:3> '
    }
    Invoke-PromptTest 'a location change prevents reuse' {
        $directory = Join-Path $HOME 'different-directory'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-HookPromptInput -Line ''
        Push-Location $directory
        try { Assert-Equal (prompt) 'render:4> ' } finally { Pop-Location }
    }
    Invoke-PromptTest 'blank prompts keep reporting terminal prompt boundaries' {
        $null = prompt
        $writer = [IO.StringWriter]::new()
        try {
            [Console]::SetOut($writer)
            Set-HookPromptInput -Line ''
            $null = prompt
            if (-not $writer.ToString().Contains(']133;A')) { throw 'prompt marker missing' }
            if (-not $writer.ToString().Contains('SetUserVar=BUSY=MA==')) { throw 'idle state missing' }
        } finally {
            [Console]::SetOut([IO.TextWriter]::Null)
            $writer.Dispose()
        }
    }
    Invoke-PromptTest 'window width changes prevent reuse' {
        & $hook { $script:CachedPromptWidth = -1 }
        $before = $global:PromptRenderCount
        Set-HookPromptInput -Line ''
        $null = prompt
        Assert-Equal $global:PromptRenderCount ($before + 1)
    }
    Invoke-PromptTest 'prompt preserves native exit status' {
        $global:LASTEXITCODE = 7
        $null = prompt
        Assert-Equal $global:LASTEXITCODE 7
        Set-HookPromptInput -Line ''
        $null = prompt
        Assert-Equal $global:LASTEXITCODE 7
        $global:LASTEXITCODE = 0
    }
    Invoke-PromptTest 'candidate display redraws reuse the prompt without terminal status events' {
        $null = prompt
        $before = $global:PromptRenderCount
        $writer = [IO.StringWriter]::new()
        try {
            & $hook { $script:CompletionDisplayState = [pscustomobject]@{ Line = 'git pull origin ' } }
            [Console]::SetOut($writer)
            foreach ($index in 1..3) {
                Assert-Equal (prompt) "render:$before> "
            }
            Assert-Equal $global:PromptRenderCount $before
            Assert-Equal $writer.ToString() ''
        } finally {
            & $hook { $script:CompletionDisplayState = $null }
            [Console]::SetOut([IO.TextWriter]::Null)
            $writer.Dispose()
        }
        Set-HookPromptInput -Line 'Write-Output done'
        Assert-Equal (prompt) "render:$($before + 1)> "
        Assert-Equal $global:PromptRenderCount ($before + 1)
    }
    Invoke-PromptTest 'candidate redraw refreshes on window width changes without terminal events' {
        $before = $global:PromptRenderCount
        $writer = [IO.StringWriter]::new()
        try {
            & $hook {
                $script:CompletionDisplayState = [pscustomobject]@{ Line = 'git pull origin ' }
                $script:CachedPromptWidth = -1
            }
            [Console]::SetOut($writer)
            $null = prompt
            $null = prompt
            Assert-Equal $global:PromptRenderCount ($before + 1)
            Assert-Equal $writer.ToString() ''
        } finally {
            & $hook { $script:CompletionDisplayState = $null }
            [Console]::SetOut([IO.TextWriter]::Null)
            $writer.Dispose()
        }
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
