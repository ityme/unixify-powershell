# 终端状态上报。不绑按键。
# 协议细节（OSC、WEZTERM_*、$env:WEZTERM_PANE）留在本文件。

function Test-TermPane {
    [bool]$env:WEZTERM_PANE
}

function Get-TermWorkingDirectory {
    try {
        return $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    } catch {
        try {
            return (Get-Location).Path
        } catch {
            return ''
        }
    }
}

function Write-TermUserVariable {
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_]+$')]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value = ''
    )

    if (-not (Test-TermPane)) {
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

    $location = Get-TermWorkingDirectory
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

function Write-TermPaneTitle {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    if (-not (Test-TermPane)) {
        return
    }

    try {
        $title = Get-WezTermPaneTitle -Command $Command
        [Console]::Write([char]0x1b + ']2;' + $title + [char]0x07)
    } catch {
        # 标题上报失败不应阻断命令执行或提示符。
    }
}

function Write-TermWorkingDirectoryUri {
    param([string]$Path)

    if (-not (Test-TermPane) -or -not $Path) {
        return
    }

    try {
        $uri = [Uri]::new($Path).AbsoluteUri
        [Console]::Write([char]0x1b + ']7;' + $uri + [char]0x1b + '\')
    } catch {
    }
}

function Sync-TermCommand {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    Write-TermUserVariable -Name 'WEZTERM_COMMAND' -Value $Command
    Write-TermPaneTitle -Command $Command
}

function Sync-TermPrompt {
    Write-TermUserVariable -Name 'WEZTERM_SHELL' -Value 'pwsh'
    Sync-TermCommand -Command ''
    $location = Get-TermWorkingDirectory
    Write-TermUserVariable -Name 'WEZTERM_CWD' -Value $location
    Write-TermWorkingDirectoryUri -Path $location
}

Export-ModuleMember -Function Get-WezTermPaneTitle, Sync-TermCommand, Sync-TermPrompt
