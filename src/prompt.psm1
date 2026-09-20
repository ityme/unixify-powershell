# Native prompt renderer; visual settings come from the selected local theme.
$script:PromptGitPath = $null
$script:PromptGitSearchKey = $null

function Get-PromptStyle {
    param([string]$Foreground, [string]$Background, [bool]$Bold, [bool]$Italic)

    $codes = [Collections.Generic.List[string]]::new()
    $codes.Add('0')
    if ($Bold) { $codes.Add('1') }
    if ($Italic) { $codes.Add('3') }
    foreach ($channel in @(@($Foreground, '38', '39'), @($Background, '48', '49'))) {
        if ($channel[0].StartsWith('#')) {
            $rgb = @(1, 3, 5 | ForEach-Object { [Convert]::ToInt32($channel[0].Substring($_, 2), 16) }) -join ';'
            $codes.Add("$($channel[1]);2;$rgb")
        } else { $codes.Add($channel[2]) }
    }
    return "$([char]27)[$($codes -join ';')m"
}

function Test-PromptModuleVisible {
    param($Module, [bool]$Succeeded)
    return $Module.Enabled -and ($Module.When -eq 'always' -or
        ($Succeeded -and $Module.When -eq 'success') -or (-not $Succeeded -and $Module.When -eq 'failure'))
}

function Resolve-PromptColor {
    param([string]$Color, $Previous, $Next, [bool]$Background)
    if ($Color -eq 'previous.background') { $Color = if ($Previous) { $Previous.Background } else { 'transparent' } }
    elseif ($Color -eq 'next.background') { $Color = if ($Next) { $Next.Background } else { 'transparent' } }
    # Terminal-default background RGB is unknown; its foreground fallback is terminal-default text.
    if (-not $Background -and $Color -eq 'transparent') { return 'default' }
    return $Color
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
    param(
        [string]$Directory = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath,
        [ValidateSet('folder', 'path')][string]$Style = 'folder'
    )

    $path = $Directory.Replace('\', '/').TrimEnd('/')
    $homePath = $HOME.Replace('\', '/').TrimEnd('/')
    if ($path.Equals($homePath, [StringComparison]::OrdinalIgnoreCase)) { return '~' }
    if ($Style -eq 'path') {
        if ($path.StartsWith($homePath + '/', [StringComparison]::OrdinalIgnoreCase)) { return '~' + $path.Substring($homePath.Length) }
        return unixpath $Directory
    }
    if ($path -match '^[A-Za-z]:$') { return (unixpath ($path + '/')).TrimEnd('/') }
    if (-not $path) { return '/' }
    return $path.Substring($path.LastIndexOf('/') + 1)
}

function Format-PromptDuration {
    param([long]$Milliseconds, [long]$MinimumMs = 2000)
    if ($Milliseconds -lt $MinimumMs) { return '' }
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

    $theme = Get-UpwshTheme
    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    $values = @{}
    $styles = @{}
    # Resolve data once, before decorations. Hidden modules contribute neither padding nor anchors.
    foreach ($id in $theme.Order) {
        if ($styles.ContainsKey($id)) { continue }
        $module = $theme.Modules[$id]
        if ($module.Type -eq 'text' -or -not (Test-PromptModuleVisible $module $Succeeded)) { continue }
        $style = @{}
        foreach ($key in @('Foreground', 'Background', 'Bold', 'Italic')) { $style[$key] = $module[$key] }
        $value = switch ($module.Type) {
            'user' { if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName } }
            'host' { [Environment]::MachineName.ToLowerInvariant().Split('.')[0] }
            'directory' {
                if ($location.Provider.Name -eq 'FileSystem') { Get-PromptPathText -Directory $location.ProviderPath -Style $module.Style }
                else { $location.Path }
            }
            'git' { if ($location.Provider.Name -eq 'FileSystem') { Get-PromptGitBranch $location.ProviderPath } }
            'duration' { if ($DurationMs -gt 0) { Format-PromptDuration $DurationMs -MinimumMs $module.MinMs } }
            'exitCode' {
                if ($Succeeded) { '0' }
                elseif ($null -ne $ExitCode -and [string]$ExitCode -notin @('', '0')) { [string]$ExitCode }
                else { '1' }
            }
            'symbol' {
                if (-not $Succeeded) {
                    foreach ($key in @('Foreground', 'Background', 'Bold', 'Italic')) {
                        if ($module.Failure.Contains($key)) { $style[$key] = $module.Failure[$key] }
                    }
                }
                if (-not $Succeeded -and $module.Failure.Contains('Text')) { $module.Failure.Text } else { $module.Text }
            }
        }
        $styles[$id] = $style
        $value = [string]$value -replace '[\x00-\x1f\x7f-\x9f\u2028\u2029]', ''
        if ($value.Length) { $values[$id] = $module.Prefix + $value + $module.Suffix }
    }
    # Neighbours are visible data modules, not other text decorations. Repeated connectors
    # resolve independently at their position and skip any number of hidden modules.
    $nextAt = @{}
    $next = $null
    for ($index = $theme.Order.Count - 1; $index -ge 0; $index--) {
        $nextAt[$index] = $next
        $id = $theme.Order[$index]
        if ($values.ContainsKey($id)) { $next = $styles[$id] }
    }
    $colored = $Color -eq 'Always' -or ($Color -eq 'Auto' -and $Host.Name -eq 'ConsoleHost' -and
        $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected -and $env:TERM -ne 'dumb' -and $null -eq $env:NO_COLOR)
    $text = [Text.StringBuilder]::new()
    $previous = $null
    for ($index = 0; $index -lt $theme.Order.Count; $index++) {
        $id = $theme.Order[$index]
        $module = $theme.Modules[$id]
        if ($module.Type -eq 'text') {
            if (-not (Test-PromptModuleVisible $module $Succeeded)) { continue }
            $attached = $true
            foreach ($target in $module.AttachTo) { if (-not $values.ContainsKey($target)) { $attached = $false; break } }
            if (-not $attached -or -not $module.Text.Length) { continue }
            $value = $module.Prefix + $module.Text + $module.Suffix
            $style = @{
                Foreground = Resolve-PromptColor $module.Foreground $previous $nextAt[$index] $false
                Background = Resolve-PromptColor $module.Background $previous $nextAt[$index] $true
                Bold = $module.Bold
                Italic = $module.Italic
            }
        } else {
            if (-not $values.ContainsKey($id)) { continue }
            $value = $values[$id]
            $style = $styles[$id]
            $previous = $style
        }
        if ($colored) { [void]$text.Append((Get-PromptStyle @style)) }
        [void]$text.Append($value)
    }
    # Reset before PSReadLine paints input; background must never leak into the command buffer.
    if ($colored) { [void]$text.Append("$([char]27)[0m") }
    return $text.ToString()
}

Export-ModuleMember -Function Get-UpwshPromptText, Get-PromptGitBranch, Get-PromptPathText
