# Local themes

[README](../README.md) · [中文主题说明](themes.zh-CN.md)

The default theme is **iWonder**. It preserves the existing prompt: green user/host, yellow italic folder, cyan branch, and a bold green or red `❯`.

```powershell
upwsh theme list
upwsh theme install "iWonder"
```

`list` reads local JSON files and marks the active theme with `*`. `install` selects a theme that already exists locally; it does not download anything. The next prompt uses it without reloading the entire shell or opening another window. A selection made by `upwsh.cmd` or another session is detected when the loaded prompt next runs; it cannot redraw another window while that window is idle.

## Bundled themes

| Theme | Appearance | Recommended terminal background |
| --- | --- | --- |
| [iWonder](../src/themes/iWonder.json) | Original green/yellow/cyan palette, italic folder, `❯` | Dark |
| [Glacier](../src/themes/Glacier.json) | Ice-blue folder, lavender branch, no italics | Dark |
| [Ember](../src/themes/Ember.json) | Amber folder, warm-white branch, no italics | Dark |
| [Quiet](../src/themes/Quiet.json) | Neutral folder and branch; hides user/host and duration; `>` on success, `!` on failure | Dark |
| [Daylight](../src/themes/Daylight.json) | Deep-blue folder, purple branch, no italics | Light |

All five show the current folder, Git branch, and numeric failure code. Except Quiet, they show user/host and duration from two seconds. Themes change foreground text only: choose the terminal's background and font in WezTerm or Windows Terminal. Daylight does not switch the terminal to light mode.

For example, after installing/updating the runtime:

```powershell
upwsh theme install "Glacier"
upwsh theme install "iWonder"  # Restore the default appearance
```

## Files

```text
~/.config/upwsh/
  themes/
    iWonder.json
    Glacier.json
    Ember.json
    Quiet.json
    Daylight.json
    My Theme.json
  custom/
    theme.json
```

The selection file contains only a filename:

```json
{"Theme":"iWonder.json"}
```

Without a selection file, the prompt uses iWonder. An invalid selection keeps the last usable theme in the session, or falls back to iWonder in a new session. Invalid themes are skipped by `list`; selecting one reports an error and leaves the existing selection unchanged.

Install and update preserve existing `themes/` files and `custom/theme.json`, adding only missing bundled themes. That also preserves older bundled files without the new comments; find the annotated versions in the table above rather than overwriting your edits. Uninstall removes theme files along with the runtime; `--keep-custom` preserves the selection file but not `themes/`, so back up your own themes before uninstalling.

## Customize

Each bundled JSON file includes a `_Comment` object with Chinese explanations for every setting. It is optional metadata, ignored by the renderer. Edit the actual values under `Colors`, `Symbols`, and `Display`, not their descriptions under `_Comment`. Keep standard JSON syntax: double-quoted strings, unquoted `true`/`false`, no trailing commas or `//` comments.

Copy `themes/iWonder.json` to `themes/My Theme.json`, change `Name` to `My Theme`, and edit its values. Then select it:

```powershell
upwsh theme install "My Theme"
```

Run the same command again after editing the selected theme to reload it. Theme JSON is read only when loading or switching, not parsed on every keystroke. The prompt checks the small selection file's timestamp and size when it runs.

| Setting | Meaning |
| --- | --- |
| `Version` | Schema version; use `1` |
| `Name` | Theme name, matching its filename without `.json` |
| `Colors.UserHost`, `.Directory`, `.Branch`, `.Duration`, `.Success`, `.Error` | Foreground colors, each in `#RRGGBB` form |
| `Symbols.Success`, `.Error` | Prompt characters; 1–16 UTF-16 code units, no whitespace or terminal control characters |
| `Display.ShowUserHost`, `.ShowGitBranch`, `.ShowDuration`, `.ShowExitCode` | Show or hide segments |
| `Display.DirectoryStyle` | `folder` for the last folder name; `path` for a Unix-style path |
| `Display.DirectoryItalic`, `.SymbolBold`, `.ErrorBold` | Text attributes |
| `Display.DurationMinMs` | Integer threshold from `0` to `86400000` milliseconds; iWonder uses `2000` |
| `_Comment` | Optional explanations, not settings |

Theme names support letters, digits, spaces, `_`, and `-`, start with a letter or digit, and are limited to 80 characters with no trailing spaces. File paths and the `.json` extension are not accepted in CLI theme names. Every setting except `_Comment` in the bundled [iWonder file](../src/themes/iWonder.json) is required; duplicate it rather than starting with an empty file. Keep theme files within 64 KiB.

Theme files contain data, never executable PowerShell. They change prompt appearance only, not aliases, completion, Git queries, or OSC configuration. Hiding the Git segment also skips branch lookup during prompt rendering.

## Development

`src/theme.psm1` owns local discovery, validation, selection, and reload tracking. `src/prompt.psm1` renders that data. The CLI operates on the installed themes under `~/.config/upwsh`; loading `src/profile.ps1` directly uses source-local theme data for development.

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_theme.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt_renderer.ps1
```
