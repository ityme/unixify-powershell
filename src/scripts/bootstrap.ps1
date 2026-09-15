# 下载 unixify-powershell 并挂钩当前用户的 pwsh。
#   curl -fsSL https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.sh | bash
#   pwsh -NoLogo -NoProfile -Command "irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.ps1 | iex"
#   pwsh -NoLogo -NoProfile -File src/scripts/bootstrap.ps1
#   pwsh -NoLogo -NoProfile -File src/scripts/bootstrap.ps1 --directory ~/.config/upwsh

$script:SavedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$script:Arguments = @($args)
$script:DefaultRepo = 'ityme/unixify-powershell'
$script:DefaultRef = 'main'
$script:UserAgent = 'unixify-powershell-installer'

function Get-InstallUsage {
    @'
usage: bootstrap.ps1 [-h | --help] [-c | --check]
                     [-d | --directory <dir>] [-p | --profile <path>]
                     [--current-host] [--ref <ref>] [--repo <owner/name>]
                     [--source <dir>]

These are common bootstrap.ps1 commands used in various situations:

install this runtime
   --directory      Runtime directory, default ~/.config/upwsh
   --profile        pwsh profile to edit, default CurrentUserAllHosts
   --current-host   Write $PROFILE.CurrentUserCurrentHost
   --source         Local source tree, skip download
   --ref            Git branch or tag to download
   --repo           GitHub repository, default ityme/unixify-powershell

inspect without writing
   --check          Show hook status without copying files

A network install can run:

  curl -fsSL https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.sh | bash
  pwsh -NoLogo -NoProfile -Command "irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.ps1 | iex"

Environment: UNIXIFY_DIR UNIXIFY_REF UNIXIFY_REPO UNIXIFY_SOURCE
Pipe installs can pass options through environment variables or
'bash -s --'.
'@
}

function New-InstallParseResult {
    [pscustomobject]@{
        Help        = $false
        Error       = $null
        Check       = $false
        CurrentHost = $false
        Directory   = $null
        Profile     = $null
        Ref         = $null
        Repo        = $null
        Source      = $null
    }
}

function ConvertFrom-InstallArguments {
    param([object[]]$Tokens)

    $tokens = @(
        $Tokens |
            Where-Object { $_ -ne $null -and [string]$_ -ne '' }
    )
    $result = New-InstallParseResult
    $index = 0

    while ($index -lt $tokens.Count) {
        $token = [string]$tokens[$index]
        switch -Regex ($token) {
            '^(--help|-h)$' {
                $result.Help = $true
                return $result
            }
            '^(--check|-c)$' {
                $result.Check = $true
                $index++
            }
            '^--current-host$' {
                $result.CurrentHost = $true
                $index++
            }
            '^(--directory|-d)$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing directory'
                    return $result
                }
                $result.Directory = [string]$tokens[$index + 1]
                $index += 2
            }
            '^(--profile|-p)$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing profile path'
                    return $result
                }
                $result.Profile = [string]$tokens[$index + 1]
                $index += 2
            }
            '^--ref$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing ref'
                    return $result
                }
                $result.Ref = [string]$tokens[$index + 1]
                $index += 2
            }
            '^--repo$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing repo'
                    return $result
                }
                $result.Repo = [string]$tokens[$index + 1]
                $index += 2
            }
            '^--source$' {
                if ($index + 1 -ge $tokens.Count) {
                    $result.Help = $true
                    $result.Error = 'missing source directory'
                    return $result
                }
                $result.Source = [string]$tokens[$index + 1]
                $index += 2
            }
            default {
                $result.Help = $true
                $result.Error = "unknown option: $token"
                return $result
            }
        }
    }

    return $result
}

function ConvertTo-WindowsStyleDirectory {
    param([string]$Path)

    $windows = $Path
    $homePath = ($HOME.TrimEnd('\', '/') -replace '\\', '/')
    $windows = [regex]::Replace($windows, '(?<=^|[\s=''"])~(?=/|$|\\)', $homePath)
    $windows = [regex]::Replace(
        $windows,
        '/([A-Za-z]):',
        { param($m) $m.Groups[1].Value.ToUpperInvariant() + ':' }
    )
    return [regex]::Replace(
        $windows,
        '(?<=^|[\s=''"])/([A-Za-z])(/|$)',
        { param($m) $m.Groups[1].Value.ToUpperInvariant() + ':/' }
    )
}

function Get-DefaultDestination {
    Join-Path $HOME '.config\upwsh'
}

function Test-RuntimeRoot {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }
    (Test-Path -LiteralPath (Join-Path $Path 'profile.ps1') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path 'scripts\install_profile.ps1') -PathType Leaf)
}

function Resolve-RuntimeRoot {
    param([string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    if (Test-RuntimeRoot $full) {
        return $full
    }

    $src = Join-Path $full 'src'
    if (Test-RuntimeRoot $src) {
        return [IO.Path]::GetFullPath($src)
    }

    $dirs = @(Get-ChildItem -LiteralPath $full -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 1) {
        return Resolve-RuntimeRoot $dirs[0].FullName
    }

    throw "missing profile.ps1 under $full"
}

function Get-LocalScriptRoot {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    if ($PSCommandPath) {
        return Split-Path -Parent $PSCommandPath
    }
    return $null
}

function Get-SiblingRuntimeRoot {
    $here = Get-LocalScriptRoot
    if (-not $here) {
        return $null
    }

    $current = $here
    while ($current) {
        try {
            return Resolve-RuntimeRoot $current
        } catch {
        }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return $null
}

function Get-GitHubHeaders {
    @{
        'User-Agent' = $script:UserAgent
        Accept       = 'application/vnd.github+json'
    }
}

function Get-LatestReleaseZipUri {
    param([string]$Repo)

    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$Repo/releases/latest" `
        -Headers (Get-GitHubHeaders)
    $asset = @(
        $release.assets |
            Where-Object { $_.name -like '*.zip' -and $_.browser_download_url }
    )[0]
    if (-not $asset) {
        throw "release has no zip: $Repo"
    }
    $asset.browser_download_url
}

function Get-ArchiveZipUri {
    param([string]$Repo, [string]$Ref)

    $encoded = [uri]::EscapeDataString($Ref)
    if ($Ref -match '^v\d' -or $Ref -like 'refs/tags/*') {
        $tag = $Ref -replace '^refs/tags/', ''
        return "https://github.com/$Repo/archive/refs/tags/$([uri]::EscapeDataString($tag)).zip"
    }
    "https://github.com/$Repo/archive/refs/heads/$encoded.zip"
}

function Save-Uri {
    param([string]$Uri, [string]$Path)

    Invoke-WebRequest `
        -Uri $Uri `
        -OutFile $Path `
        -Headers @{ 'User-Agent' = $script:UserAgent } `
        -UseBasicParsing |
        Out-Null
}

function Get-DownloadedRuntime {
    param(
        [string]$Repo,
        [string]$Ref
    )

    $work = Join-Path ([IO.Path]::GetTempPath()) (
        'unixify-powershell-' + [Guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $zip = Join-Path $work 'source.zip'
        $extract = Join-Path $work 'extract'
        New-Item -ItemType Directory -Path $extract -Force | Out-Null

        $uris = [Collections.Generic.List[string]]::new()
        if ($Ref) {
            $uris.Add((Get-ArchiveZipUri -Repo $Repo -Ref $Ref)) | Out-Null
        } else {
            try {
                $uris.Add((Get-LatestReleaseZipUri -Repo $Repo)) | Out-Null
            } catch {
                $uris.Add((Get-ArchiveZipUri -Repo $Repo -Ref $script:DefaultRef)) | Out-Null
            }
        }

        $saved = $false
        $lastError = $null
        foreach ($uri in $uris) {
            try {
                Save-Uri -Uri $uri -Path $zip
                $saved = $true
                break
            } catch {
                $lastError = $_
            }
        }
        if (-not $saved) {
            throw "download failed: $($lastError.Exception.Message)"
        }

        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        [pscustomobject]@{
            Root = (Resolve-RuntimeRoot $extract)
            Work = $work
        }
    } catch {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Complete-Install {
    param(
        [int]$Code,
        $Invocation = $MyInvocation
    )

    $ErrorActionPreference = $script:SavedErrorActionPreference
    $global:LASTEXITCODE = $Code
    if (-not $PSCommandPath -or $Invocation.CommandOrigin -eq 'Runspace') {
        exit $Code
    }
}

$parsed = ConvertFrom-InstallArguments -Tokens $script:Arguments
$scriptInvocation = $MyInvocation
if ($parsed.Help) {
    if ($parsed.Error) {
        Write-Output "unixify-powershell: $($parsed.Error)"
        Write-Output ''
    }
    Get-InstallUsage
    if ($parsed.Error) {
        Complete-Install 2 $scriptInvocation
        return
    }
    Complete-Install 0 $scriptInvocation
    return
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'unixify-powershell: need PowerShell 7'
    Complete-Install 1 $scriptInvocation
    return
}

$repo = if ($parsed.Repo) {
    $parsed.Repo
} elseif ($env:UNIXIFY_REPO) {
    $env:UNIXIFY_REPO
} else {
    $script:DefaultRepo
}
$ref = if ($parsed.Ref) { $parsed.Ref } elseif ($env:UNIXIFY_REF) { $env:UNIXIFY_REF } else { $null }
$source = if ($parsed.Source) {
    $parsed.Source
} elseif ($env:UNIXIFY_SOURCE) {
    $env:UNIXIFY_SOURCE
} else {
    $null
}
$directory = if ($parsed.Directory) {
    $parsed.Directory
} elseif ($env:UNIXIFY_DIR) {
    $env:UNIXIFY_DIR
} else {
    Get-DefaultDestination
}
$directory = [IO.Path]::GetFullPath((ConvertTo-WindowsStyleDirectory $directory))

$workRoot = $null
try {
    $forceRemote = [bool]$ref -or [bool]$parsed.Repo
    $sibling = $null
    if (-not $source -and -not $forceRemote) {
        $sibling = Get-SiblingRuntimeRoot
    }
    if ($source) {
        $runtimeRoot = Resolve-RuntimeRoot (ConvertTo-WindowsStyleDirectory $source)
    } elseif ($sibling) {
        $runtimeRoot = $sibling
    } else {
        $downloaded = Get-DownloadedRuntime -Repo $repo -Ref $ref
        $runtimeRoot = $downloaded.Root
        $workRoot = $downloaded.Work
    }

    $installer = Join-Path $runtimeRoot 'scripts\install_profile.ps1'
    $installerArgs = @{}
    if ($parsed.Profile) {
        $installerArgs.ProfilePath = [IO.Path]::GetFullPath(
            (ConvertTo-WindowsStyleDirectory $parsed.Profile)
        )
    }
    if ($parsed.CurrentHost) {
        $installerArgs.CurrentHost = $true
    }
    if ($parsed.Check) {
        $installerArgs.Check = $true
    } else {
        $installerArgs.Deploy = $true
        $installerArgs.Destination = $directory
    }

    Write-Output ("dir      {0}" -f $directory)
    Write-Output ("source   {0}" -f $runtimeRoot)
    & $installer @installerArgs
    Complete-Install 0 $scriptInvocation
} catch {
    Write-Output "unixify-powershell: $($_.Exception.Message)"
    Complete-Install 1 $scriptInvocation
} finally {
    if ($workRoot -and (Test-Path -LiteralPath $workRoot)) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
