# Native renderer matching the user's Starship "pure" visual reference, not a TOML interpreter.
$script:PromptGitPath = $null
$script:PromptGitSearchKey = $null
$script:PromptPalette = @{
    UserHost = '34;197;94'   # #22C55E
    Directory = '234;179;8' # #EAB308, italic
    Branch = '6;182;212'    # #06B6D4
    Duration = '115;218;202' # #73DACA
    Success = '13;180;71'   # #0DB447, bold
    Error = '209;91;113'    # #D15B71, bold
}

function Get-PromptGitExecutable {
    $key = @($env:PATH, $env:PATHEXT, $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath) -join [char]0
    if ($script:PromptGitSearchKey -ceq $key -and $script:PromptGitPath -and [IO.File]::Exists($script:PromptGitPath)) {
        return $script:PromptGitPath
    }
    $command = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:PromptGitPath = if ($command) { $command.Source } else { $null }
    $script:PromptGitSearchKey = $key
    return $script:PromptGitPath
}

function Invoke-PromptGit {
    param([string]$Directory, [string[]]$Arguments)

    $git = Get-PromptGitExecutable
    if (-not $git) { return '' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $git
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    foreach ($argument in @('--no-optional-locks', '-C', $Directory) + $Arguments) {
        [void]$start.ArgumentList.Add($argument)
    }
    $process = $null
    try {
        $process = [Diagnostics.Process]::Start($start)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(250)) {
            $process.Kill($true)
            $process.WaitForExit()
            return ''
        }
        $text = $stdout.GetAwaiter().GetResult().TrimEnd("`r", "`n")
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -eq 0) { return $text }
    } catch {
        # Git metadata is optional; failure must not prevent entering a command.
    } finally {
        if ($process) { $process.Dispose() }
    }
    return ''
}

function Get-PromptBranchFromHead {
    param([string]$HeadPath)

    try { $head = [IO.File]::ReadAllText($HeadPath).Trim() } catch { return '' }
    if ($head -match '^ref: refs/heads/(.+)$') { return $Matches[1] }
    if ($head -match '^[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?$') { return 'detached@' + $head.Substring(0, 7) }
    return ''
}

function Get-PromptGitBranch {
    param([string]$Directory)

    $head = [IO.Path]::Combine($Directory, '.git', 'HEAD')
    if ([IO.File]::Exists($head) -and -not $env:GIT_DIR -and -not $env:GIT_WORK_TREE) {
        return Get-PromptBranchFromHead $head
    }
    # Let Git locate HEAD in subdirectories/worktrees, including branches with no commits.
    $head = Invoke-PromptGit $Directory @('rev-parse', '--git-path', 'HEAD')
    if (-not $head) { return '' }
    if (-not [IO.Path]::IsPathRooted($head)) { $head = [IO.Path]::Combine($Directory, $head) }
    # hook.psm1 caches idle prompt text; actual renders must not reuse a stale branch or miss.
    return Get-PromptBranchFromHead $head
}

function Get-PromptPathText {
    param([string]$Directory = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath)

    $path = $Directory.Replace('\', '/').TrimEnd('/')
    $homePath = $HOME.Replace('\', '/').TrimEnd('/')
    if ($path.Equals($homePath, [StringComparison]::OrdinalIgnoreCase)) { return '~' }
    if ($path -match '^[A-Za-z]:$') { return (unixpath ($path + '/')).TrimEnd('/') }
    if (-not $path) { return '/' }
    return $path.Substring($path.LastIndexOf('/') + 1)
}

function Format-PromptDuration {
    param([long]$Milliseconds)
    # Starship cmd_duration defaults to min_time=2000; min_time_to_notify is unrelated.
    if ($Milliseconds -lt 2000) { return '' }
    $value = [TimeSpan]::FromTicks($Milliseconds * [TimeSpan]::TicksPerMillisecond)
    $text = if ($value.Days -gt 0) { "$($value.Days)d$($value.Hours)h$($value.Minutes)m$($value.Seconds)s" }
        elseif ($value.Hours -gt 0) { "$($value.Hours)h$($value.Minutes)m$($value.Seconds)s" }
        elseif ($value.Minutes -gt 0) { "$($value.Minutes)m$($value.Seconds)s" }
        else { "$($value.Seconds)s" }
    return $text + "$($value.Milliseconds)ms"
}

function Get-UpwshPromptText {
    param(
        [bool]$Succeeded = $true,
        $ExitCode = 0,
        [long]$DurationMs = 0,
        [ValidateSet('Auto', 'Always', 'Never')][string]$Color = 'Auto'
    )

    $user = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
    $hostName = [Environment]::MachineName.ToLowerInvariant().Split('.')[0]
    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    if ($location.Provider.Name -eq 'FileSystem') {
        $path = Get-PromptPathText -Directory $location.ProviderPath
        $branch = Get-PromptGitBranch $location.ProviderPath
    } else { $path = $location.Path; $branch = '' }
    $userHost = ("$user@$hostName" -replace '[\x00-\x1f\x7f-\x9f]', '') + ' '
    $path = ($path -replace '[\x00-\x1f\x7f-\x9f]', '') + ' '
    $branchText = if ($branch) { ($branch -replace '[\x00-\x1f\x7f-\x9f]', '') + ' ' } else { '' }
    $duration = Format-PromptDuration $DurationMs
    $code = if ($Succeeded) { '' } elseif ($null -ne $ExitCode -and [string]$ExitCode -notin @('', '0')) { [string]$ExitCode } else { '1' }
    $code = $code -replace '[\x00-\x1f\x7f-\x9f]', ''
    $colored = $Color -eq 'Always' -or ($Color -eq 'Auto' -and $Host.Name -eq 'ConsoleHost' -and
        $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected -and $env:TERM -ne 'dumb' -and $null -eq $env:NO_COLOR)
    if (-not $colored) { return "$userHost$path$branchText$duration$code❯ " }

    $esc = [char]27
    $reset = "$esc[0m"
    $palette = $script:PromptPalette
    $text = "$esc[38;2;$($palette.UserHost)m$userHost$reset$esc[3;38;2;$($palette.Directory)m$path$reset"
    if ($branchText) { $text += "$esc[38;2;$($palette.Branch)m$branchText$reset" }
    if ($duration) { $text += "$esc[38;2;$($palette.Duration)m$duration$reset" }
    if ($code) { $text += "$esc[1;38;2;$($palette.Error)m$code$reset" }
    $symbolColor = if ($Succeeded) { $palette.Success } else { $palette.Error }
    return $text + "$esc[1;38;2;${symbolColor}m❯$reset "
}

Export-ModuleMember -Function Get-UpwshPromptText, Get-PromptGitBranch, Get-PromptPathText
