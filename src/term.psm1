# 终端状态上报。不绑按键。
# 原子字段用中性名；OSC 2/7/133 是通用通道。默认写入。

$script:TermIdentity = $null
$script:TermIdentitySequences = $null
$script:TermCommandStarted = $null
$script:TermLastLocation = $null
$script:TermLastLocationSequences = $null
$script:TermUtf8 = [Text.Encoding]::UTF8
$script:TermBuilder = [Text.StringBuilder]::new(2048)
$script:TermCacheBuilder = [Text.StringBuilder]::new(1024)

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

function Get-TermIdentity {
    if ($script:TermIdentity) {
        return $script:TermIdentity
    }

    $admin = '0'
    try {
        if ([Environment]::IsPrivilegedProcess) {
            $admin = '1'
        }
    } catch {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            if ($principal.IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator
                )) {
                $admin = '1'
            }
        } catch {
        }
    }

    $ssh = '0'
    if (
        $env:SSH_CONNECTION -or
        $env:SSH_CLIENT -or
        $env:SSH_TTY
    ) {
        $ssh = '1'
    }

    $script:TermIdentity = [pscustomobject]@{
        Host   = [string]$env:COMPUTERNAME
        User   = [string]$env:USERNAME
        Domain = [string]$env:USERDOMAIN
        Admin  = $admin
        Ssh    = $ssh
        Shell  = 'pwsh'
    }
    return $script:TermIdentity
}

function Add-TermUserVariable {
    param(
        [Text.StringBuilder]$Builder,
        [string]$Name,
        [AllowEmptyString()][string]$Value = ''
    )

    [void]$Builder.Append([char]0x1b)
    [void]$Builder.Append(']1337;SetUserVar=')
    [void]$Builder.Append($Name)
    [void]$Builder.Append('=')
    [void]$Builder.Append(
        [Convert]::ToBase64String($script:TermUtf8.GetBytes($Value))
    )
    [void]$Builder.Append([char]0x07)
}

function Add-TermText {
    param(
        [Text.StringBuilder]$Builder,
        [string]$Text
    )

    if ($Text) {
        [void]$Builder.Append($Text)
    }
}

function Get-TermDirectoryLeaf {
    param([string]$Path)

    $trimmed = $Path.TrimEnd([char[]]@('\', '/'))
    if (-not $trimmed) {
        return $Path
    }
    $slash = $trimmed.LastIndexOfAny([char[]]@('\', '/'))
    if ($slash -ge 0 -and $slash -lt $trimmed.Length - 1) {
        return $trimmed.Substring($slash + 1)
    }
    return $trimmed
}

function Get-TermHomeRelativePath {
    param([string]$Path)

    if (-not $Path -or -not $HOME) {
        return $Path
    }

    $homeFull = $HOME.TrimEnd('\', '/')
    if ($Path.StartsWith($homeFull, [StringComparison]::OrdinalIgnoreCase)) {
        $rest = $Path.Substring($homeFull.Length)
        if ($rest -eq '' -or $rest.StartsWith('\') -or $rest.StartsWith('/')) {
            return '~' + ($rest -replace '\\', '/')
        }
    }
    return $Path
}

function Get-TermDrive {
    param([string]$Path)

    if ($Path.Length -ge 2 -and $Path[1] -eq [char]':') {
        $letter = $Path[0]
        if (
            ($letter -ge 'A' -and $letter -le 'Z') -or
            ($letter -ge 'a' -and $letter -le 'z')
        ) {
            return ([string]$letter).ToUpperInvariant() + ':'
        }
    }
    return ''
}

function Get-TermCommandName {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    $text = ($Command -replace '[\x00-\x1f\x7f-\x9f]', ' ' -replace '\s+', ' ').Trim()
    if ($text.StartsWith('& ')) {
        $text = $text.Substring(2).Trim()
    }
    if ($text.StartsWith("'")) {
        $end = $text.IndexOf("'", 1)
        if ($end -gt 1) {
            $text = $text.Substring(1, $end - 1)
        }
    } elseif ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -gt 1) {
            $text = $text.Substring(1, $end - 1)
        }
    } else {
        $space = $text.IndexOf(' ')
        if ($space -gt 0) {
            $text = $text.Substring(0, $space)
        }
    }

    if ($text -match '[\\/]') {
        $slash = $text.LastIndexOfAny([char[]]@('\', '/'))
        if ($slash -ge 0 -and $slash -lt $text.Length - 1) {
            return $text.Substring($slash + 1)
        }
    }
    return $text
}

function Get-TermVenvName {
    $root = $env:VIRTUAL_ENV
    if (-not $root) {
        return ''
    }
    return Get-TermDirectoryLeaf $root
}

function Get-TermIdentitySequences {
    if ($script:TermIdentitySequences) {
        return $script:TermIdentitySequences
    }

    $identity = Get-TermIdentity
    $builder = $script:TermCacheBuilder
    $builder.Clear() | Out-Null
    Add-TermUserVariable $builder 'SHELL' $identity.Shell
    Add-TermUserVariable $builder 'HOST' $identity.Host
    Add-TermUserVariable $builder 'USER' $identity.User
    Add-TermUserVariable $builder 'DOMAIN' $identity.Domain
    Add-TermUserVariable $builder 'ADMIN' $identity.Admin
    Add-TermUserVariable $builder 'SSH' $identity.Ssh
    $script:TermIdentitySequences = $builder.ToString()
    return $script:TermIdentitySequences
}

function Get-TermLocationSequences {
    param([string]$Location)

    if (
        $script:TermLastLocationSequences -and
        $script:TermLastLocation -ceq $Location
    ) {
        return $script:TermLastLocationSequences
    }

    $leaf = Get-TermDirectoryLeaf $Location
    $builder = $script:TermCacheBuilder
    $builder.Clear() | Out-Null
    Add-TermUserVariable $builder 'CWD' $Location
    Add-TermUserVariable $builder 'DIR' $leaf
    Add-TermUserVariable $builder 'CWD_HOME' (Get-TermHomeRelativePath $Location)
    Add-TermUserVariable $builder 'DRIVE' (Get-TermDrive $Location)
    Add-TermUserVariable $builder 'VENV' (Get-TermVenvName)
    if ($Location) {
        $unix = $Location -replace '\\', '/'
        if ($unix.Length -ge 2 -and $unix[1] -eq [char]':') {
            $unix = '/' + $unix
        }
        [void]$builder.Append([char]0x1b)
        [void]$builder.Append(']7;file://')
        [void]$builder.Append($unix)
        [void]$builder.Append([char]0x1b)
        [void]$builder.Append('\')
    }
    $script:TermLastLocation = $Location
    $script:TermLastLocationSequences = $builder.ToString()
    return $script:TermLastLocationSequences
}

function Get-TermPaneTitle {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    $directory = Get-TermDirectoryLeaf (Get-TermWorkingDirectory)
    $cleanCommand = ($Command -replace '[\x00-\x1f\x7f-\x9f]', ' ' -replace '\s+', ' ').Trim()
    $title = if ($cleanCommand) {
        "$directory › $(Get-TermCommandName $cleanCommand)"
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

function Write-TermBuilder {
    param([Text.StringBuilder]$Builder)

    if ($Builder.Length -eq 0) {
        return
    }
    try {
        [Console]::Write($Builder.ToString())
    } catch {
        # 状态上报失败不应阻断命令执行或提示符。
    }
}

function Sync-TermCommand {
    param(
        [AllowEmptyString()]
        [string]$Command = ''
    )

    $script:TermCommandStarted = [DateTime]::UtcNow
    $name = Get-TermCommandName $Command
    $title = Get-TermPaneTitle -Command $Command
    $builder = $script:TermBuilder
    $builder.Clear() | Out-Null
    Add-TermUserVariable $builder 'BUSY' '1'
    Add-TermUserVariable $builder 'COMMAND' $Command
    Add-TermUserVariable $builder 'CMD' $name
    [void]$builder.Append([char]0x1b)
    [void]$builder.Append(']2;')
    [void]$builder.Append($title)
    [void]$builder.Append([char]0x07)
    [void]$builder.Append([char]0x1b)
    [void]$builder.Append(']133;C')
    [void]$builder.Append([char]0x07)
    Write-TermBuilder $builder
}

function Sync-TermPrompt {
    param(
        [bool]$Succeeded = $true,
        $ExitCode
    )

    $location = Get-TermWorkingDirectory
    $elapsed = ''
    if ($script:TermCommandStarted) {
        $elapsed = [string][int](
            ([DateTime]::UtcNow - $script:TermCommandStarted).TotalMilliseconds
        )
        $script:TermCommandStarted = $null
    }

    $ok = if ($Succeeded) { '1' } else { '0' }
    $exit = if ($Succeeded) {
        '0'
    } elseif ($null -ne $ExitCode -and [string]$ExitCode -ne '') {
        [string]$ExitCode
    } else {
        '1'
    }

    $title = Get-TermPaneTitle
    $builder = $script:TermBuilder
    $builder.Clear() | Out-Null
    [void]$builder.Append([char]0x1b)
    [void]$builder.Append(']133;D;')
    [void]$builder.Append($exit)
    [void]$builder.Append([char]0x07)
    [void]$builder.Append([char]0x1b)
    [void]$builder.Append(']133;A')
    [void]$builder.Append([char]0x07)
    Add-TermText $builder (Get-TermIdentitySequences)
    Add-TermText $builder (Get-TermLocationSequences $location)
    Add-TermUserVariable $builder 'COMMAND' ''
    Add-TermUserVariable $builder 'CMD' ''
    Add-TermUserVariable $builder 'BUSY' '0'
    Add-TermUserVariable $builder 'OK' $ok
    Add-TermUserVariable $builder 'EXIT' $exit
    Add-TermUserVariable $builder 'ELAPSED_MS' $elapsed
    [void]$builder.Append([char]0x1b)
    [void]$builder.Append(']2;')
    [void]$builder.Append($title)
    [void]$builder.Append([char]0x07)
    [void]$builder.Append([char]0x1b)
    [void]$builder.Append(']133;B')
    [void]$builder.Append([char]0x07)
    Write-TermBuilder $builder
}

Export-ModuleMember -Function @(
    'Get-TermPaneTitle'
    'Get-TermCommandName'
    'Sync-TermCommand'
    'Sync-TermPrompt'
)
