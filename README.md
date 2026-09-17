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

Copies the runtime to `~/.config/upwsh`, then loads it into pwsh.

The install directory is fixed at `~/.config/upwsh`. `UPWSH_HOME` records this path; changing it does not move the installation.

In this project or a subdirectory, `upwsh install` uses local `src/` files. Outside the project, it downloads the source. Use `--source`, `--ref`, or `--repo` to choose a source; piped installs accept `UPWSH_SOURCE`, `UPWSH_REF`, and `UPWSH_REPO`.

Open a new `pwsh`. `upwsh --help` should work.

## Commands

After `load`, this pwsh has `ll`, `cd`, completion, and `upwsh`. New pwsh windows get the same from `$PROFILE`. The `upwsh` command on Path is `%UPWSH_HOME%\bin\upwsh.cmd`.

| Command | What it does |
| --- | --- |
| `upwsh install` | Install from the local project or a download into `~/.config/upwsh`, then load |
| `upwsh update` | Reinstall `~/.config/upwsh` using the same source rules; preserve `custom/` |
| `upwsh uninstall` | Remove the startup hook, managed Path entries, `UPWSH_HOME`, and `~/.config/upwsh` |
| `upwsh load` | Load `~/.config/upwsh/profile.ps1` into pwsh and configure it to load at startup |
| `upwsh unload` | Stop `$PROFILE` from loading it. Files, Path, and `upwsh` stay |
| `upwsh tool list` | List CLIs and whether they are on Path |
| `upwsh tool install [names…]` | Install CLIs into `tool\bin` |
| `upwsh tool uninstall <names…>` | Remove named CLIs |

`load` also sets user `UPWSH_HOME` and appends `%UPWSH_HOME%\bin` and `%UPWSH_HOME%\tool\bin` to the user Path. Run `install` first; `load` does not load the source tree. `unload` stops future automatic loading but leaves the current session unchanged.

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

If `upwsh` is already installed, run `upwsh install` from this clone to install your local changes. Both commands copy `src/` into `~/.config/upwsh`; neither uses the clone as the install directory.

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

## Prompt performance

Empty Enter reuses the previous prompt. Commands, directory changes, and window width changes refresh it. Starship remains available; its Git, clock, and other dynamic segments refresh after a command, not on empty Enter.

Measure on Windows (p95 target: 30ms for empty Enter):

```powershell
pwsh -NoLogo -NoProfile -File src/tests/bench_prompt.ps1 -Enforce
python src/tests/bench_console.py --enforce
```

The first measures the prompt path; the second sends Enter through Windows ConPTY. Startup and first-prompt times are reported separately. These timings exclude the terminal application's screen painting.

## Tests

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_path_commands.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
