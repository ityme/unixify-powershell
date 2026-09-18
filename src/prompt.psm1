# Fast native prompt. Starship remains optional as a separate tool, not a runtime dependency.
$script:PromptGitPath = $null
$script:PromptGitPathKey = $null
$script:PromptGitContextKey = $null
$script:PromptGitHeadMarker = $null
$script:PromptGitBranch = ''

function Get-PromptGitExecutable {
    if ($script:PromptGitPath -and $script:PromptGitPathKey -ceq $env:PATH) {
        if ([IO.File]::Exists($script:PromptGitPath)) { return $script:PromptGitPath }
    }
    $command = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $script:PromptGitPath = if ($command) { $command.Source } else { $null }
    $script:PromptGitPathKey = $env:PATH
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
    foreach ($argument in @('-C', $Directory, '--no-optional-locks') + $Arguments) {
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
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -eq 0) {
            return $stdout.GetAwaiter().GetResult().Trim()
        }
    } catch {
    } finally {
        if ($process) { $process.Dispose() }
    }
    return ''
}

function Get-PromptBranchFromHead {
    param([string]$HeadPath)

    if (-not [IO.File]::Exists($HeadPath)) { return '' }
    try { $head = [IO.File]::ReadAllText($HeadPath).Trim() } catch { return '' }
    if ($head -match '^ref: refs/heads/(.+)$') { return $Matches[1] }
    if ($head -match '^[0-9a-fA-F]{7,64}$') { return 'detached@' + $head.Substring(0, [Math]::Min(7, $head.Length)) }
    return ''
}

function Get-PromptGitBranch {
    param([string]$Directory)

    $head = Join-Path $Directory '.git\HEAD'
    $headMarker = if ([IO.File]::Exists($head)) {
        try { [IO.File]::GetLastWriteTimeUtc($head).Ticks.ToString() + ':' + [IO.File]::ReadAllText($head).Trim() } catch { 'unreadable' }
    } else { '' }
    $contextKey = "$Directory|$head"
    if ($script:PromptGitContextKey -ceq $contextKey -and $script:PromptGitHeadMarker -ceq $headMarker) {
        return $script:PromptGitBranch
    }
    $branch = Get-PromptBranchFromHead $head
    if (-not $branch) {
        $branch = Invoke-PromptGit -Directory $Directory -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($branch -eq 'HEAD') { $branch = '' }
        if (-not $branch) {
            $commit = Invoke-PromptGit -Directory $Directory -Arguments @('rev-parse', '--short', 'HEAD')
            if ($commit) { $branch = 'detached@' + $commit }
        }
    }
    $script:PromptGitContextKey = $contextKey
    $script:PromptGitHeadMarker = $headMarker
    $script:PromptGitBranch = $branch
    return $branch
}

function Get-PromptPathText {
    $path = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    $home = $HOME.TrimEnd('\', '/')
    if ($path -ieq $home) { return '~' }
    if ($path.StartsWith($home + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return '~/' + $path.Substring($home.Length + 1).Replace('\', '/')
    }
    return unixpath $path
}

function Get-UpwshPromptText {
    param(
        [bool]$Succeeded = $true,
        $ExitCode = 0
    )

    $user = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
    $hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }
    $path = Get-PromptPathText
    $branch = Get-PromptGitBranch -Directory $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    $prefix = "$user@$hostName $path"
    if ($branch) { $prefix += " $branch" }
    $symbol = if ($Succeeded) { '>' } else { '!' }

    $color = $Host.Name -eq 'ConsoleHost' -and
        $Host.UI.SupportsVirtualTerminal -and
        -not [Console]::IsOutputRedirected
    if (-not $color) { return "$prefix$symbol " }

    $esc = [char]27
    $userHost = "$esc[32m$user@$hostName$esc[0m"
    $coloredPath = "$esc[33m$path$esc[0m"
    $coloredBranch = if ($branch) { " $esc[36m$branch$esc[0m" } else { '' }
    $coloredSymbol = if ($Succeeded) { "$esc[32m>$esc[0m" } else { "$esc[31m!$esc[0m" }
    "$userHost $coloredPath$coloredBranch$coloredSymbol "
}

Export-ModuleMember -Function Get-UpwshPromptText, Get-PromptGitBranch, Get-PromptPathText
