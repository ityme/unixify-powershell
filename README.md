# unixify-powershell

Unix-style PowerShell 7 on Windows: paths, commands, and tab-complete.

[English](README.md) | [简体中文](README.zh-CN.md)

## Before / after

Stock pwsh uses Windows paths and cmdlets. After `load`, you type Unix paths and Unix commands. Tab-complete stays Unix too. Execution still uses Windows paths.

| Before | After |
| --- | --- |
| `Set-Location I:\ispace` | `cd /i/ispace` |
| `cd $HOME\Desktop` | `cd ~/Desktop` |
| `Get-ChildItem` | `ls` |
| `Get-ChildItem -Force` | `ll` |
| `Copy-Item -Recurse src backup` | `cp -r src backup` |
| `Move-Item old.txt new.txt` | `mv old.txt new.txt` |
| `New-Item -ItemType Directory -Force logs\archive` | `mkdir -p logs/archive` |
| `Remove-Item -Recurse -Force build` | `rm -rf build` |
| `Select-String error app.log` | `grep error app.log` |
| `Get-Command nvim` | `which nvim` |
| Tab `I:\ispace\foo\` | `/i/ispace/foo/` |

## Install

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

Copies the runtime to `~/.config/upwsh`, then loads it into pwsh.

Home: `$env:UPWSH_HOME`, else the user `UPWSH_HOME` variable, else `~/.config/upwsh`.

```powershell
$env:UPWSH_HOME = "$HOME\.config\upwsh"
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

Pipe options: `UPWSH_REF`, `UPWSH_REPO`. Next to this repo, `install.ps1` copies `src/` and skips the download.

Open a new `pwsh`. `upwsh --help` should work.

## Commands

After `load`, this pwsh has `ll`, `cd`, completion, and `upwsh`. New pwsh windows get the same from `$PROFILE`. The `upwsh` command on Path is `%UPWSH_HOME%\bin\upwsh.cmd`.

| Command | What it does |
| --- | --- |
| `upwsh install` | Copy the runtime to home, then load |
| `upwsh update` | Uninstall, keep `custom`, then install |
| `upwsh uninstall` | Unload, then delete `UPWSH_HOME`, Path entries, and the home tree |
| `upwsh load` | Load into this pwsh, and into `$PROFILE` so later pwsh sessions load too |
| `upwsh unload` | Stop `$PROFILE` from loading it. Files, Path, and `upwsh` stay |
| `upwsh tool list` | List CLIs and whether they are on Path |
| `upwsh tool install [names…]` | Install CLIs into `tool\bin` |
| `upwsh tool uninstall <names…>` | Remove named CLIs |

`load` also sets user `UPWSH_HOME` and appends `%UPWSH_HOME%\bin` and `%UPWSH_HOME%\tool\bin` to the user Path.

Personal files: `$UPWSH_HOME\custom\*.ps1`. Sample shortcuts are in `custom\alias.ps1` (`w`, `t`, `i`, `d`, `gs`). `update` keeps this folder.

## Layout

```
~/.config/upwsh/
  profile.ps1
  scripts/
  bin/upwsh.cmd      # the upwsh command
  tool/bin/          # eza, rg, …
  custom/alias.ps1   # sample shortcuts (w, t, i, d, gs)
```

## From a clone

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/install.ps1
```

Load this tree into pwsh without copying:

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 load
```

## Update

```powershell
upwsh update
```

## Uninstall

```powershell
upwsh uninstall
```

Stop `$PROFILE` from loading it (keep files and Path):

```powershell
upwsh unload
```

Does not delete a git checkout.

## Tests

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
