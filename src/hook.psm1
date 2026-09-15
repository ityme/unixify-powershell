# 按键与 prompt 管道。
#
# Tab:  completion -> path
# Enter: term command -> path rewrite -> accept
# prompt: starship -> term

$script:SkipConvertedHistory = $false

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

function Get-CommandLineName {
    param([string]$Line)

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $Line,
        [ref]$tokens,
        [ref]$parseErrors
    )
    foreach ($token in $tokens) {
        $kind = [string]$token.Kind
        if ($kind -in @('Identifier', 'Generic', 'Command')) {
            return $token.Text
        }
    }
    return ''
}

function Test-WindowsCommandLineReplacement {
    param(
        [string]$Original,
        [string]$Converted
    )

    if ($Converted -ceq $Original) {
        return $false
    }

    $trimmed = $Original.Trim()
    if (
        $trimmed -notmatch '\s' -and
        (Test-PathLikeToken $trimmed)
    ) {
        return $true
    }

    $name = Get-CommandLineName $Original
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $false
    }

    $command = Get-Command $name -ErrorAction SilentlyContinue
    while ($command -and $command.CommandType -eq 'Alias') {
        $command = Get-Command $command.Definition -ErrorAction SilentlyContinue
    }
    return [bool](
        $command -and
        $command.CommandType -eq 'Application'
    )
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
    $state = Invoke-PowerShellCompletionHook -State $state
    $state = Invoke-PathCompletionHook -State $state
    return $state
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

    $state = Complete-HookLine -Line $inputScript -Cursor $cursorColumn
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

if ($Host.Name -eq 'ConsoleHost' -and (Get-Module PSReadLine -ListAvailable)) {
    Import-Module PSReadLine
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
            -CurrentText $currentText

        if ($decision.MatchCount -eq 1) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                $state.ReplacementIndex,
                $state.ReplacementLength,
                $decision.Replacement
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

            [Microsoft.PowerShell.PSConsoleReadLine]::PossibleCompletions()
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
            'WezTermAcceptLine'
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
        Invoke-Expression (& $starshipCommand.Source init powershell)
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
    $promptText = & $script:BasePrompt
    Sync-TermPrompt
    return $promptText
}

Export-ModuleMember -Function Complete-HookLine, Test-CompleteCommandLine, Test-WindowsCommandLineReplacement
