# 按键与 prompt 管道。
#
# Tab:  completion -> path
# Enter: term command -> path rewrite -> accept
# prompt: starship -> term

$script:SkipConvertedHistory = $false
$script:ReusePrompt = $false
$script:CachedPrompt = $null
$script:CachedPromptLocation = $null
$script:CachedPromptWidth = 0

function Set-HookPromptInput {
    param([AllowEmptyString()][string]$Line = '')

    $script:ReusePrompt = [string]::IsNullOrWhiteSpace($Line)
    if (-not $script:ReusePrompt) {
        Clear-GitCompletionCache
    }
}

function Test-CompleteCommandLine {
    param(
        [AllowEmptyString()]
        [string]$InputScript = ''
    )

    if ([string]::IsNullOrWhiteSpace($InputScript)) {
        return $false
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $InputScript,
        [ref]$tokens,
        [ref]$parseErrors
    )

    return -not @(
        $parseErrors | Where-Object IncompleteInput
    ).Count
}

function Test-WindowsCommandLineReplacement {
    param(
        [string]$Original,
        [string]$Converted
    )

    if ($Converted -ceq $Original) {
        return $false
    }

    return $true
}

function New-HookState {
    param(
        [string]$Line,
        [int]$Cursor
    )

    [pscustomobject]@{
        Line               = $Line
        Cursor             = $Cursor
        ReplacementIndex   = 0
        ReplacementLength  = 0
        Matches            = @()
        LiteralPaths       = $false
        MatchesNormalized  = $false
        SpaceAfterWord     = $false
    }
}

function Complete-HookLine {
    param(
        [string]$Line,
        [int]$Cursor = -1
    )

    if ($Cursor -lt 0) {
        $Cursor = $Line.Length
    }

    $state = New-HookState -Line $Line -Cursor $Cursor
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
    $git = Get-GitCompletion -Line $Line -Cursor $Cursor -Ast $ast
    if ($null -ne $git) {
        $state.ReplacementIndex = $git.ReplacementIndex
        $state.ReplacementLength = $git.ReplacementLength
        $state.Matches = $git.Matches
        $state.MatchesNormalized = $true
        $state.SpaceAfterWord = $true
        return $state
    }
    $commands = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)
    $pathElement = $null
    foreach ($command in $commands) {
        if ($command.Extent.StartOffset -le $Cursor -and $command.Extent.EndOffset -ge $Cursor) {
            $state.LiteralPaths = $command.GetCommandName() -in @('winpath', 'unixpath')
            $pathElement = $null
            foreach ($element in $command.CommandElements | Select-Object -Skip 1) {
                if ($element -is [Management.Automation.Language.StringConstantExpressionAst] -and
                    $element.Extent.StartOffset -lt $Cursor -and $element.Extent.EndOffset -ge $Cursor -and
                    $element.Value -match '^(?:\.{1,2}[/\\]|~[/\\]|/[A-Za-z](?:/|$)|/?[A-Za-z]:[/\\])') {
                    $pathElement = $element
                }
            }
        }
    }
    if ($pathElement) {
        $state.ReplacementIndex = $pathElement.Extent.StartOffset
        $state.ReplacementLength = $pathElement.Extent.EndOffset - $pathElement.Extent.StartOffset
        $state = Invoke-PathCompletionHook -State $state
        if ($state.Matches.Count -gt 0) {
            $state.MatchesNormalized = $true
            return $state
        }
    }
    $state = Invoke-PowerShellCompletionHook -State $state
    $state = Invoke-PathCompletionHook -State $state
    $state.MatchesNormalized = $true
    return $state
}

function Get-HookCompletionEdit {
    param($State, $Decision)

    $length = $State.ReplacementLength
    $text = $Decision.Replacement
    if ($State.SpaceAfterWord -and $Decision.MatchCount -eq 1) {
        $end = $State.ReplacementIndex + $length
        if ($end -eq $State.Line.Length) {
            $text += ' '
        } elseif ($State.Line[$end] -in @([char]' ', [char]9)) {
            # Consume and reinsert one existing separator so Replace also advances the cursor.
            $text += $State.Line[$end]
            $length++
        }
    }
    [pscustomobject]@{ Start = $State.ReplacementIndex; Length = $length; Text = $text }
}

function global:TabExpansion2 {
    [CmdletBinding(DefaultParameterSetName = 'ScriptInputSet')]
    param(
        [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 0)]
        [string]$inputScript,

        [Parameter(ParameterSetName = 'ScriptInputSet', Mandatory, Position = 1)]
        [int]$cursorColumn,

        [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 0)]
        [System.Management.Automation.Language.Ast]$ast,

        [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 1)]
        [System.Management.Automation.Language.Token[]]$tokens,

        [Parameter(ParameterSetName = 'AstInputSet', Mandatory, Position = 2)]
        [System.Management.Automation.Language.IScriptPosition]$positionOfCursor,

        [Parameter(ParameterSetName = 'ScriptInputSet', Position = 2)]
        [Parameter(ParameterSetName = 'AstInputSet', Position = 3)]
        [Hashtable]$options = $null
    )

    if ($PSCmdlet.ParameterSetName -eq 'AstInputSet') {
        $inputScript = $ast.Extent.Text
        $cursorColumn = $positionOfCursor.Offset
    }

    # PossibleCompletions calls TabExpansion2 again; reuse this keypress's candidates only.
    $state = $script:CompletionDisplayState
    if (-not $state -or $state.Line -cne $inputScript -or $state.Cursor -ne $cursorColumn) {
        $state = Complete-HookLine -Line $inputScript -Cursor $cursorColumn
    }
    $results = [System.Collections.ObjectModel.Collection[System.Management.Automation.CompletionResult]]::new()
    foreach ($match in @($state.Matches)) {
        $results.Add($match)
    }

    return [System.Management.Automation.CommandCompletion]::new(
        $results,
        -1,
        $state.ReplacementIndex,
        $state.ReplacementLength
    )
}

if ($Host.Name -eq 'ConsoleHost' -and -not (Get-Module PSReadLine)) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
}
if ($Host.Name -eq 'ConsoleHost' -and (Get-Module PSReadLine)) {
    Set-PSReadLineOption -CompletionQueryItems 60
    Set-PSReadLineOption -AddToHistoryHandler {
        param($lineToBeAdded)
        if ($script:SkipConvertedHistory) {
            $script:SkipConvertedHistory = $false
            return $false
        }
        -not [string]::IsNullOrWhiteSpace($lineToBeAdded)
    }
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -PredictionSource None

    Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
        $line = $null
        $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $state = Complete-HookLine -Line $line -Cursor $cursor
        $currentText = ''
        if (
            $state.ReplacementIndex -ge 0 -and
            $state.ReplacementLength -ge 0 -and
            $state.ReplacementIndex -le $line.Length -and
            $state.ReplacementLength -le ($line.Length - $state.ReplacementIndex)
        ) {
            $currentText = $line.Substring(
                $state.ReplacementIndex,
                $state.ReplacementLength
            )
        }

        $decision = Get-CompletionDecision `
            -Matches $state.Matches `
            -CurrentText $currentText `
            -LiteralPaths:$state.LiteralPaths `
            -Normalized:$state.MatchesNormalized

        if ($decision.MatchCount -eq 1) {
            $edit = Get-HookCompletionEdit -State $state -Decision $decision
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                $edit.Start,
                $edit.Length,
                $edit.Text
            )
            return
        }

        $currentHasGlob = (
            -not $currentText.StartsWith("'") -and
            -not $currentText.StartsWith('"') -and
            $currentText -match '[*?]'
        )

        if ($decision.MatchCount -gt 1) {
            if (
                -not $currentHasGlob -and
                $decision.Replacement -and
                -not $decision.Replacement.Equals(
                    $currentText,
                    [StringComparison]::OrdinalIgnoreCase
                )
            ) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                    $state.ReplacementIndex,
                    $state.ReplacementLength,
                    $decision.Replacement
                )
                return
            }

            $script:CompletionDisplayState = $state
            try {
                [Microsoft.PowerShell.PSConsoleReadLine]::PossibleCompletions()
            } finally {
                $script:CompletionDisplayState = $null
            }
        }
    }

    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Chord Ctrl+r -ScriptBlock {
            $historyPath = (Get-PSReadLineOption).HistorySavePath
            $selection = Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue |
                fzf --tac --no-sort --height=40% --border

            if ($selection) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert(
                    ($selection -join [Environment]::NewLine)
                )
            }
        }
    }

    $enterHandler = Get-PSReadLineKeyHandler -Chord Enter
    if ($enterHandler.Function -in @(
            'AcceptLine'
            'ValidateAndAcceptLine'
            'HookAcceptLine'
        )) {
        Set-PSReadLineKeyHandler `
            -Chord Enter `
            -BriefDescription 'HookAcceptLine' `
            -LongDescription 'Path rewrite then accept line' `
            -ScriptBlock {
                param($key, $arg)

                $line = $null
                $cursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
                    [ref]$line,
                    [ref]$cursor
                )
                Set-HookPromptInput -Line $line
                if (Test-CompleteCommandLine -InputScript $line) {
                    Sync-TermCommand -Command $line
                    $rewritten = ConvertTo-WindowsCommandLine -InputScript $line
                    if (
                        $rewritten -cne $line -and
                        (Test-WindowsCommandLineReplacement -Original $line -Converted $rewritten)
                    ) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
                        $script:SkipConvertedHistory = $true
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                            0,
                            $line.Length,
                            $rewritten
                        )
                    }
                }

                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($key, $arg)
            }
    }
}

$starshipCommand = Get-Command starship -ErrorAction SilentlyContinue
if ($starshipCommand) {
    $promptCommand = Get-Command prompt -ErrorAction SilentlyContinue
    if (-not $promptCommand -or $promptCommand.Source -ne 'starship') {
        Invoke-Expression (& $starshipCommand.Source init powershell --print-full-init | Out-String)
    }
    if (Get-Module PSReadLine) {
        $psReadLineOptions = Get-PSReadLineOption
        if ($psReadLineOptions.EditMode -ne 'Vi') {
            Set-PSReadLineOption -ViModeIndicator None
        }
    }
}

if (-not (Test-Path Variable:script:BasePrompt)) {
    $script:BasePrompt = (Get-Command prompt).ScriptBlock
}

function global:prompt {
    $succeeded = $?
    $exitCode = $global:LASTEXITCODE
    $location = $ExecutionContext.SessionState.Path.CurrentLocation.Path
    $width = $Host.UI.RawUI.WindowSize.Width
    $reuse = $script:ReusePrompt -and
        $null -ne $script:CachedPrompt -and
        $location -ceq $script:CachedPromptLocation -and
        $width -eq $script:CachedPromptWidth
    $script:ReusePrompt = $false
    try {
        # No command ran on an empty Enter; keep Starship and its subprocesses off this path.
        if (-not $reuse) {
            $script:CachedPrompt = & $script:BasePrompt
            $script:CachedPromptLocation = $location
            $script:CachedPromptWidth = $width
        }
        Sync-TermPrompt -Succeeded $succeeded -ExitCode $exitCode
        return $script:CachedPrompt
    } finally {
        $global:LASTEXITCODE = $exitCode
    }
}

Export-ModuleMember -Function Complete-HookLine, Test-CompleteCommandLine, Test-WindowsCommandLineReplacement, Set-HookPromptInput
