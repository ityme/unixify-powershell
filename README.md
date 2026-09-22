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

Two families, 12 local themes. **`pure-default`** is the default (formerly iWonder). Switch without restarting pwsh:

```powershell
upwsh theme list
upwsh theme use "colorful-blue"
upwsh theme use "pure-default"
```

### pure-* · transparent backgrounds

![Five pure themes: default, glacier, ember, quiet and daylight](docs/assets/themes/pure.png)

| Theme | Appearance |
| --- | --- |
| [pure-default](src/themes/pure-default.json) | Original green user/host, yellow italic folder, cyan branch |
| [pure-glacier](src/themes/pure-glacier.json) | Ice-blue folder, lavender branch |
| [pure-ember](src/themes/pure-ember.json) | Amber folder, warm-white branch |
| [pure-quiet](src/themes/pure-quiet.json) | Minimal: hides user/host and duration; `>` on success, `!` on failure |
| [pure-daylight](src/themes/pure-daylight.json) | Deep blue and purple for a light terminal background |

### colorful-* · connected color blocks

![Seven colorful themes with connected user, host, directory and Git segments](docs/assets/themes/colorful.png)

| Theme | Palette |
| --- | --- |
| [colorful-blue](src/themes/colorful-blue.json) | Deep teal → lake green → bright teal → ice teal |
| [colorful-green](src/themes/colorful-green.json) | Sage → matcha → spring green → pale mint |
| [colorful-macaron](src/themes/colorful-macaron.json) | Lilac → sky blue → lake green → soft green |
| [colorful-morandi](src/themes/colorful-morandi.json) | Sage grey → dusty pink → oat → linen |
| [colorful-cyberpunk](src/themes/colorful-cyberpunk.json) | Neon purple → electric blue → aqua → ice blue |
| [colorful-retro](src/themes/colorful-retro.json) | Forest green → ochre → warm tan → ivory |
| [colorful-memphis](src/themes/colorful-memphis.json) | Pink → lemon yellow → cyan → pale blue |

Colorful follows the approved `starship-colorful.toml` palette reference. User, host, folder and Git form a connected strip; duration, exit code and `❯` keep transparent backgrounds. Missing Git, short commands and successful commands hide their conditional segments without leaving orphan arrows. Foreground readability corrections are recorded in each JSON's `_Comment.ContrastAdjustments`.

Colorful enables `AddNewline` for one blank line before the prompt; pure disables it. One space follows the color strip, then duration, exit code and symbol join as in pure: ` 6s418ms1❯`.

Screenshots show sample user/host, branch `dev`, exit code `7`, and duration `2.345s`; Quiet hides duration. Dark previews use `#1a1b26`, Daylight uses white. Terminal backgrounds are not changed by selecting a theme. **Colorful needs Powerline glyphs**, for example JetBrainsMono Nerd Font.

For an interactive comparison of all eight command states, download the repository and open **[docs/themes.html](docs/themes.html)** in a browser. It works offline; GitHub may show the HTML source rather than run it.

Themes live in `~/.config/upwsh/themes/`; personal themes live in `~/.config/upwsh/custom/themes/`; `custom/theme.json` records the selection. V2 uses `Order` and `Modules` for colors, layout and attached connectors. Each JSON includes Chinese field explanations. Switching refreshes the next prompt; editing requires reselecting the theme.

Updates refresh bundled themes in `themes/` and preserve personal themes in `custom/themes/` plus the selection file. Old names are not aliases or automatically renamed. **V1 themes are unsupported**: back them up before upgrading. See [Themes](docs/themes.md) for upgrade steps and configuration.

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
