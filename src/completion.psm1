# 补全 hook：只向 PowerShell 要候选，不转换路径。

function Invoke-PowerShellCompletionHook {
    param($State)

    $completion = [System.Management.Automation.CommandCompletion]::CompleteInput(
        $State.Line,
        $State.Cursor,
        $null
    )

    $State.ReplacementIndex = $completion.ReplacementIndex
    $State.ReplacementLength = $completion.ReplacementLength
    $State.Matches = @($completion.CompletionMatches)
    return $State
}

Export-ModuleMember -Function Invoke-PowerShellCompletionHook
