# Run lifecycle tests without touching the real user profile, registry, or install.
function Invoke-UpwshTestProcess {
    param(
        [Parameter(Mandatory)][string]$UserHome,
        [string]$Command,
        [string]$File,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $UserHome,
        [hashtable]$Environment = @{}
    )

    New-Item -ItemType Directory -Path $UserHome -Force | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $WorkingDirectory
    $start.Environment['USERPROFILE'] = $UserHome
    $start.Environment['UPWSH_TEST_ISOLATED'] = '1'
    $start.Environment['UPWSH_PROFILE'] = Join-Path $UserHome 'test-profile.ps1'
    $start.Environment['UPWSH_SKIP_PERSIST_PATH'] = '1'
    $start.Environment['UPWSH_SKIP_SESSION_LOAD'] = '1'
    $start.Environment['UPWSH_SKIP_RELAUNCH'] = '1'
    foreach ($name in @('UPWSH_HOME', 'UPWSH_SOURCE', 'UPWSH_REF', 'UPWSH_REPO', 'UPWSH_UNINSTALL_REEXEC', 'UPWSH_UNINSTALL_WAIT_PID')) {
        [void]$start.Environment.Remove($name)
    }
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) {
            [void]$start.Environment.Remove($name)
        } else {
            $start.Environment[$name] = [string]$Environment[$name]
        }
    }
    foreach ($token in @('-NoLogo', '-NoProfile')) {
        [void]$start.ArgumentList.Add($token)
    }
    if ($File) {
        [void]$start.ArgumentList.Add('-File')
        [void]$start.ArgumentList.Add($File)
        foreach ($token in $Arguments) {
            [void]$start.ArgumentList.Add($token)
        }
    } else {
        [void]$start.ArgumentList.Add('-EncodedCommand')
        [void]$start.ArgumentList.Add([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command)))
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill($true)
            throw 'test process timed out'
        }
        [pscustomobject]@{
            Code = $process.ExitCode
            Text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-UpwshIsolatedTest {
    param([string]$File)

    $testHome = Join-Path ([IO.Path]::GetTempPath()) ('upwsh-test-user-' + [Guid]::NewGuid().ToString('N'))
    try {
        $result = Invoke-UpwshTestProcess -UserHome $testHome -File $File
        Write-Output $result.Text
        $global:LASTEXITCODE = $result.Code
    } finally {
        Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-TestLiteral {
    param([string]$Value)
    "'" + $Value.Replace("'", "''") + "'"
}
