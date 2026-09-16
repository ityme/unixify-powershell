# 由 tools / upwsh tool 调用。工具装到 $UPWSH_HOME\tool\bin。
#   tools --help
#   tools list
#   tools install eza rg
#   tools uninstall eza

[CmdletBinding()]
param(
    [string[]]$Only = @(),
    [switch]$List,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\upwsh_home.ps1')
$Dir = Get-UpwshToolBin

$script:Tools = @(
    @{ Name = 'bat'; Repo = 'sharkdp/bat'; Exe = 'bat.exe' }
    @{ Name = 'btm'; Repo = 'ClementTsang/bottom'; Exe = 'btm.exe' }
    @{ Name = 'delta'; Repo = 'dandavison/delta'; Exe = 'delta.exe' }
    @{ Name = 'dust'; Repo = 'bootandy/dust'; Exe = 'dust.exe' }
    @{ Name = 'eza'; Repo = 'eza-community/eza'; Exe = 'eza.exe' }
    @{ Name = 'fd'; Repo = 'sharkdp/fd'; Exe = 'fd.exe' }
    @{ Name = 'fzf'; Repo = 'junegunn/fzf'; Exe = 'fzf.exe' }
    @{ Name = 'hyperfine'; Repo = 'sharkdp/hyperfine'; Exe = 'hyperfine.exe' }
    @{ Name = 'jq'; Repo = 'jqlang/jq'; Exe = 'jq.exe' }
    @{ Name = 'lazygit'; Repo = 'jesseduffield/lazygit'; Exe = 'lazygit.exe' }
    @{ Name = 'procs'; Repo = 'dalance/procs'; Exe = 'procs.exe' }
    @{ Name = 'rg'; Repo = 'BurntSushi/ripgrep'; Exe = 'rg.exe' }
    @{ Name = 'shfmt'; Repo = 'mvdan/sh'; Exe = 'shfmt.exe' }
    @{ Name = 'starship'; Repo = 'starship/starship'; Exe = 'starship.exe' }
    @{ Name = 'tssh'; Repo = 'trzsz/trzsz-ssh'; Exe = 'tssh.exe' }
    @{ Name = 'yazi'; Repo = 'sxyazi/yazi'; Exe = 'yazi.exe' }
    @{ Name = 'yq'; Repo = 'mikefarah/yq'; Exe = 'yq.exe' }
    @{ Name = 'zoxide'; Repo = 'ajeetdsouza/zoxide'; Exe = 'zoxide.exe' }
)

function Test-WindowsAmd64Asset {
    param([string]$Name)

    if ($Name -match '\.(sha256|sha256sum|sig|deb|rpm|txt|json)$') {
        return $false
    }
    if ($Name -match 'arm|aarch64|i686|386|darwin|linux|musl|gnu') {
        return $false
    }
    return $Name -match 'windows|win64|msvc'
}

function Get-GitHubLatestRelease {
    param([string]$Repo)

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) {
        return gh api "repos/$Repo/releases/latest" | ConvertFrom-Json
    }

    Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$Repo/releases/latest" `
        -Headers @{
            'User-Agent' = 'unixify-powershell-installer'
            Accept       = 'application/vnd.github+json'
        }
}

function Get-ReleaseAsset {
    param($Release, [string]$Exe)

    $preferred = @(
        $Release.assets |
            Where-Object {
                $_.name -and
                (Test-WindowsAmd64Asset $_.name) -and
                (
                    $_.name -like '*.zip' -or
                    $_.name -like '*.exe'
                )
            }
    )
    if ($preferred.Count -eq 0) {
        return $null
    }

    $exeStem = [IO.Path]::GetFileNameWithoutExtension($Exe)
    $named = @(
        $preferred |
            Where-Object { $_.name -match [regex]::Escape($exeStem) }
    )
    if ($named.Count -gt 0) {
        return $named[0]
    }
    return $preferred[0]
}

function Test-CliToolCommand {
    param([string]$Name)

    $null -ne (
        Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    )
}

function Write-CliToolListLine {
    param([string]$Name, [bool]$Installed)

    $reset = $PSStyle.Reset
    if ($Installed) {
        $mark = "$($PSStyle.Foreground.Green)+$reset"
        $state = "$($PSStyle.Foreground.Green)installed$reset"
    } else {
        $mark = "$($PSStyle.Foreground.Yellow)-$reset"
        $state = "$($PSStyle.Foreground.Yellow)uninstalled$reset"
    }
    Write-Output ("{0} {1,-10} {2}" -f $mark, $Name, $state)
}

function Uninstall-CliTool {
    param($Tool, [string]$Destination)

    $target = Join-Path $Destination $Tool.Exe
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Output "skip  $($Tool.Name) (missing $target)"
        return
    }
    Remove-Item -LiteralPath $target -Force
    Write-Output "ok    $($Tool.Name) removed $target"
}

function Install-CliTool {
    param($Tool, [string]$Destination)

    $target = Join-Path $Destination $Tool.Exe
    if (Test-Path -LiteralPath $target) {
        Write-Output "skip  $($Tool.Name) (already $target)"
        return
    }

    $release = Get-GitHubLatestRelease -Repo $Tool.Repo
    $asset = Get-ReleaseAsset -Release $release -Exe $Tool.Exe
    if (-not $asset) {
        throw "no Windows amd64 asset for $($Tool.Repo)"
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
        'cli-install-' + [Guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    try {
        $download = Join-Path $tempRoot $asset.name
        Write-Output "get   $($Tool.Name) $($release.tag_name) ($($asset.name))"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download -UseBasicParsing

        if ($asset.name -like '*.zip') {
            Expand-Archive -LiteralPath $download -DestinationPath $tempRoot -Force
            $extracted = Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter $Tool.Exe |
                Select-Object -First 1
        } else {
            $extracted = Get-Item -LiteralPath $download
        }

        if (-not $extracted) {
            throw "archive had no $($Tool.Exe)"
        }

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Copy-Item -LiteralPath $extracted.FullName -Destination $target -Force
        Write-Output "ok    $($Tool.Name) -> $target"
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$names = @(
    $Only |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
$selected = @(
    $script:Tools |
        Where-Object { $names.Count -eq 0 -or $_.Name -in $names }
)
if ($names.Count -gt 0) {
    $unknown = @($names | Where-Object { $_ -notin @($script:Tools.Name) })
    if ($unknown.Count -gt 0) {
        throw "unknown tools: $($unknown -join ', ')"
    }
}

if ($List -and $Uninstall) {
    throw 'Use either -List or -Uninstall, not both.'
}
if ($Uninstall -and $names.Count -eq 0) {
    throw 'missing tool name'
}

if ($List) {
    foreach ($tool in $selected) {
        Write-CliToolListLine `
            -Name $tool.Name `
            -Installed:(Test-CliToolCommand $tool.Name)
    }
    return
}

New-Item -ItemType Directory -Path $Dir -Force | Out-Null
Write-Output "dir   $Dir"
foreach ($tool in $selected) {
    if ($Uninstall) {
        Uninstall-CliTool -Tool $tool -Destination $Dir
        continue
    }
    Install-CliTool -Tool $tool -Destination $Dir
}

if (-not $Uninstall) {
    $resolvedDir = [IO.Path]::GetFullPath($Dir)
    $onPath = $false
    foreach ($entry in @($env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        try {
            if ([IO.Path]::GetFullPath($entry) -eq $resolvedDir) {
                $onPath = $true
                break
            }
        } catch {
        }
    }
    if (-not $onPath) {
        Write-Output "warn  $Dir is not on PATH"
    }
}
