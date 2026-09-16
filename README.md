# unixify-powershell

Unix-style commands, completion, and profile for PowerShell 7 on Windows.

[English](README.md) | [简体中文](README.zh-CN.md)

## Install

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

Copies the runtime to `~/.config/upwsh` and runs `upwsh load`.

Home: `$env:UPWSH_HOME`, else the user `UPWSH_HOME` variable, else `~/.config/upwsh`.

```powershell
$env:UPWSH_HOME = "$HOME\.config\upwsh"
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

Pipe options: `UPWSH_REF`, `UPWSH_REPO`. Next to this repo, `install.ps1` copies `src/` and skips the download.

Open a new `pwsh`. `upwsh --help` should work.

## Commands

After load, run `upwsh`. From Path: `%UPWSH_HOME%\bin\upwsh.cmd`.

| Command | What it does |
| --- | --- |
| `upwsh install` | Copy the runtime to home, then load |
| `upwsh update` | Uninstall, keep `custom`, then install |
| `upwsh uninstall` | Unload, then remove `UPWSH_HOME`, Path, and the home tree |
| `upwsh load` | Load the runtime into pwsh |
| `upwsh unload` | Unload the runtime from pwsh |
| `upwsh tool list` | List CLIs and whether they are on Path |
| `upwsh tool install [names…]` | Install CLIs into `tool\bin` |
| `upwsh tool uninstall <names…>` | Remove named CLIs |

`load` writes `UPWSH_HOME`, appends `%UPWSH_HOME%\bin` and `%UPWSH_HOME%\tool\bin` to the user Path, and hooks `$PROFILE.CurrentUserAllHosts`. `unload` only removes that hook. Path and `UPWSH_HOME` stay, so `upwsh` still runs.

Personal files: `$UPWSH_HOME\custom\*.ps1` (empty by default). `update` keeps this folder.

## Layout

```
~/.config/upwsh/
  profile.ps1
  scripts/
  bin/upwsh.cmd      # the upwsh command
  tool/bin/          # eza, rg, …
  custom/            # yours
```

## From a clone

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/install.ps1
```

Load this tree without copying:

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

Unload only (keep files and Path):

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
