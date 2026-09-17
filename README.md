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

## Paths

At the interactive prompt, standalone **unquoted** `/c/...` and `~/...` arguments are converted before execution. Quoted text, comments, embedded scripts, redirections, and combined option values such as `--output=/c/a` stay unchanged. Pipelines and command chains are handled argument by argument, without command-specific rules.

Use explicit conversion for paths with spaces, variables, or paths inside scripts:

```powershell
winpath '/c/my work'          # C:/my work
unixpath 'C:\my work'         # /c/my work
cd (winpath '~/my work')
'C:\one', 'D:\two' | unixpath
```

Both commands accept multiple paths or pipeline input. They do not require paths to exist or expand wildcards. `C:relative` keeps its drive-relative meaning. PowerShell and the called program retain their own argument semantics.

Tab completion inserts `(winpath '…')` when an absolute Unix path needs quoting. In scripts and custom functions, use `winpath` explicitly; the Enter hook only rewrites interactive input.

## Install

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

Installs into `~/.config/upwsh` and enables startup loading on first install. Open a new pwsh to use it.

The install directory is fixed at `~/.config/upwsh`. `UPWSH_HOME` records this path; changing it does not move the installation.

In this project or a subdirectory, `upwsh install` uses local `src/` files. Outside the project, it downloads the source. Use `--source`, `--ref`, or `--repo` to choose a source; piped installs accept `UPWSH_SOURCE`, `UPWSH_REF`, and `UPWSH_REPO`.

Open a new `pwsh`. `upwsh --help` should work.

## Commands

The enabled profile provides `ll`, `cd`, completion, and `upwsh` when pwsh starts. The command on Path is `%UPWSH_HOME%\bin\upwsh.cmd`.

| Command | What it does |
| --- | --- |
| `upwsh install` | Install or repair `~/.config/upwsh`; first install enables startup loading |
| `upwsh update` | Update an existing installation; preserve custom, tools, and enabled/disabled state |
| `upwsh uninstall` | Remove the startup hook, managed Path entries, `UPWSH_HOME`, and `~/.config/upwsh` |
| `upwsh load` | Enable startup loading; also load the current session when called through the pwsh function |
| `upwsh unload` | Stop `$PROFILE` from loading it. Files, Path, and `upwsh` stay |
| `upwsh tool list` | List CLIs and whether they are on Path |
| `upwsh tool install [names…]` | Install CLIs into `tool\bin` |
| `upwsh tool uninstall <names…>` | Remove named CLIs |

`install` manages `UPWSH_HOME`, user Path entries `%UPWSH_HOME%\bin` / `%UPWSH_HOME%\tool\bin`, and the command shim. `load` / `unload` only change startup loading. When called through `upwsh.cmd` or `pwsh -File`, `load` cannot change the parent shell; open a new pwsh. `unload` leaves already-loaded functions in the current session.

Personal files: `$UPWSH_HOME\custom\*.ps1`. Sample shortcuts are in `custom\alias.ps1` (`w`, `t`, `i`, `d`, `gs`). Reinstall and update keep this folder and installed tools.

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

If `upwsh` is already installed, run `upwsh install` from this clone to install your local changes. Both commands copy `src/` into `~/.config/upwsh`; neither uses the clone as the install directory.

## Update

```powershell
upwsh update
```

Install and update prepare and validate the replacement before changing the live installation. Deployment errors restore the previous files and configuration. Update requires an installation and keeps a disabled profile disabled. Open a new pwsh after either command to use the new code.

## Uninstall

```powershell
upwsh uninstall
```

Stop `$PROFILE` from loading it (keep files and Path):

```powershell
upwsh unload
```

Does not delete a git checkout.

## Prompt performance

Empty Enter reuses the previous prompt. Commands, directory changes, and window width changes refresh it. Starship remains available; its Git, clock, and other dynamic segments refresh after a command, not on empty Enter.

Measure on Windows (p95 target: 30ms for empty Enter):

```powershell
pwsh -NoLogo -NoProfile -File src/tests/bench_prompt.ps1 -Enforce
python src/tests/bench_console.py --enforce
```

The first measures the prompt path; the second sends Enter through Windows ConPTY. Startup and first-prompt times are reported separately. These timings exclude the terminal application's screen painting.

Measure terminal reports and file completion separately:

```powershell
pwsh -NoLogo -NoProfile -File src/tests/bench_interaction.ps1 -Files 1000 -Samples 10
```

Explicit path completion queries the filesystem first; candidate display reuses that keypress's results. Each subsequent Tab queries again to pick up filesystem changes. Idle terminal reports reuse encoded text until the directory, virtual environment, result, or enabled fields change.

## Development

Path format conversion uses `winpath` and `unixpath` from `src/path_convert.ps1`. Interactive rewriting, completion, command output, and setup share these interfaces. Standalone installers embed generated copies so `irm | iex` also works before installation.

After changing the converter, refresh and check those copies:

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/sync_path_convert.ps1
pwsh -NoLogo -NoProfile -File src/scripts/sync_path_convert.ps1 -Check
```

## Tests

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_path_commands.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_interaction.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
