# WezTerm 上报。不绑按键。

function Write-WezTermUserVariable {
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_]+$')]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value = ''
    )

    if (-not $env:WEZTERM_PANE) {
        return
    }

    try {
        $encodedValue = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($Value)
        )
        [Console]::Write(
            [char]0x1b + ']1337;SetUserVar=' + $Name + '=' +
                $encodedValue + [char]0x07
        )
    } catch {
        # 状态上报失败不应阻断命令执行或提示符。
    }
}

function Get-WezTermPaneTitle {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    try {
        $location = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    } catch {
        $location = (Get-Location).Path
    }

    $trimmedLocation = $location.TrimEnd([char[]]@('\', '/'))
    $directory = if ($trimmedLocation) {
        Split-Path -Leaf $trimmedLocation
    } else {
        $location
    }
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = $location
    }

    # OSC 2 不能接收控制字符；多行命令压成一行，避免改变终端解析状态。
    $cleanCommand = ($Command -replace '[\x00-\x1f\x7f-\x9f]', ' ' -replace '\s+', ' ').Trim()
    $title = if ($cleanCommand) {
        "$directory › $cleanCommand"
    } else {
        $directory
    }
    $title = ($title -replace '[\x00-\x1f\x7f-\x9f]', ' ').Trim()

    $maximumLength = 160
    if ($title.Length -gt $maximumLength) {
        return $title.Substring(0, $maximumLength - 3) + '...'
    }
    return $title
}

function Write-WezTermPaneTitle {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    if (-not $env:WEZTERM_PANE) {
        return
    }

    try {
        $title = Get-WezTermPaneTitle -Command $Command
        [Console]::Write([char]0x1b + ']2;' + $title + [char]0x07)
    } catch {
        # 标题上报失败不应阻断命令执行或提示符。
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

Export-ModuleMember -Function Get-WezTermPaneTitle, Test-CompleteCommandLine, Write-WezTermPaneTitle, Write-WezTermUserVariable
