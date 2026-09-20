# unixify-powershell

A native Unix-style prompt, paths, commands, and Tab completion for **PowerShell 7 on Windows**.

The prompt follows this shape:

```text
ityme@win project dev ❯
```

The path segment shows only the current folder name (`~` at home); outside a Git repository, the branch is omitted. Colors and `❯` follow the Starship visual reference: a failed command adds its numeric error code in red, and commands lasting at least two seconds show their duration. The native renderer reads local `.git/HEAD` first, using Git to locate it in subdirectories and worktrees. It does not run Starship.

[简体中文](README.zh-CN.md)

Use `/c/Users` and `~/projects`, run familiar commands such as `ls`, `cp -r`, and `grep`, and complete paths with forward slashes. Your shell still uses PowerShell syntax and pipelines.

| Task | PowerShell | With unixify-powershell |
| --- | --- | --- |
| Change directory | `cd I:\ispace` | `cd /i/ispace` |
| List files | `Get-ChildItem` | `ls` / `ll` (via eza) |
| Copy a directory | `Copy-Item -Recurse src backup` | `cp -r src backup` |
| Search a file | `Select-String error app.log` | `grep error app.log` |
| Complete a path with Tab | `I:\ispace\project\` | `/i/ispace/project/` |

## Install

Run in PowerShell 7 (`pwsh`):

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

This installs into `~/.config/upwsh` and configures PowerShell to load it at startup. **Open a new pwsh**, then install eza for `ls`, `ll`, and `tree`:

```powershell
upwsh tool install eza
```

## Use paths

At the interactive prompt, write paths with a lowercase drive prefix and forward slashes:

```powershell
cd /i/ispace
cd ~/Desktop
cd -                         # Return to the previous directory
```

Standalone, unquoted `/c/...` and `~/...` arguments are converted to Windows paths before execution. Quoted text stays unchanged, so strings such as `'use /c/demo'` keep their meaning.

For paths with spaces, variables, or paths in scripts, use `winpath`. Use `unixpath` for the reverse conversion:

```powershell
winpath '/c/my work'          # C:/my work
unixpath 'C:\my work'         # /c/my work
cd (winpath '~/my work')
'C:\one', 'D:\two' | unixpath
```

Both commands accept multiple paths and pipeline input; paths need not exist. Tab inserts `(winpath '…')` when an absolute Unix path needs quoting. Comments, embedded scripts, redirections, and combined arguments such as `--output=/c/a` are not automatically rewritten.

## Git completion

With Git on Path, press Tab to complete common commands, branches, tags, and configured remotes:

```text
git sw<Tab>                  → git switch
git switch fe<Tab>           → matching local branches
git checkout v<Tab>          → matching tags and other refs
git push o<Tab>              → origin
git pull origin <Tab>        → locally known branches for origin
git checkout -- ./<Tab>      → files
```

A unique Git word completes with a trailing space, so you can type `git pul<Tab>o<Tab>d<Tab>` without inserting spaces when each prefix has one match. Ambiguous prefixes and directory completions do not add a space.

This uses local Git data only, with no extra dependencies. `git -C <directory>` and `git switch --track` are supported. Less common syntax falls back to normal completion. Queries are cached for one second; entering a command clears the cache. Changes made in another terminal may take up to one second to appear.

## Prompt refresh

The prompt shows a snapshot from the last completed command. Empty Enter, comments, Ctrl+L, Tab, and Ctrl+C while editing reuse it. Executing a command, including a failed or interrupted command, refreshes it once. Directory or window-width changes also refresh it.

Changes made in another window, such as switching a branch in the same working tree, appear after your next command here. Run `git status` to check the repository and refresh the prompt.

## Manage the installation

| Command | Purpose |
| --- | --- |
| `upwsh install` | Install or repair; first install enables startup loading |
| `upwsh update` | Update an existing installation, keeping custom settings, tools, and enabled/disabled state |
| `upwsh load` | Enable startup loading of `~/.config/upwsh/profile.ps1` |
| `upwsh unload` | Disable startup loading; keep files, tools, and the `upwsh` command |
| `upwsh uninstall` | Remove the installation, startup configuration, and managed environment variables and Path entries |

Open a new pwsh after installing or updating. When you call the loaded `upwsh` function, `load` also applies the profile to that session. `unload` leaves the current session unchanged. To uninstall while keeping personal settings, use `upwsh uninstall --keep-custom`.

The install directory is fixed at `~/.config/upwsh`; `UPWSH_HOME` records it. The native prompt in `src/prompt.psm1` follows the current folder and Git branch. Run `upwsh --help` for command help.

## CLI tools

Install tools as needed into `~/.config/upwsh/tool/bin`:

```powershell
upwsh tool list
upwsh tool install eza rg fd fzf
upwsh tool uninstall rg
```

## Themes

The default theme is **iWonder**. List local themes or switch without restarting pwsh:

```powershell
upwsh theme list
upwsh theme install "iWonder"
```

Themes live in `~/.config/upwsh/themes/`; `custom/theme.json` records the selected filename. Switching validates the theme and refreshes the next prompt. Install/update preserve your local themes and selection. See [Themes](docs/themes.md) for configurable colors, symbols, and display options.

## Personal settings

Edit `~/.config/upwsh/custom/alias.ps1` to change the supplied `w`, `t`, `i`, `d`, and `gs` shortcuts. You can also add your own `custom/*.ps1` files; PowerShell loads them in filename order after the built-in configuration.

For example, put this in `custom/work.ps1`:

```powershell
function global:work { cd (winpath '/i/my work') }
```

Reinstall and update preserve your files and fill in missing template files. Open a new pwsh to load your changes.

Terminal status reporting is configurable from `custom/` too. Full command text is off by default; see [Terminal Reporting](docs/terminal-reporting.md) for fields and privacy settings.

## Install from source

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/install.ps1
```

Once installed, run `upwsh install` or `upwsh update` from this project to deploy local `src/` changes. Outside the project, the commands download the source. You can override the source with `--source`, `--ref`, or `--repo`; piped installs use `UPWSH_SOURCE`, `UPWSH_REF`, and `UPWSH_REPO`.

See [Development](docs/development.md) for tests, performance benchmarks, and converter maintenance.
