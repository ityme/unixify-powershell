# Local themes (v2)

[README](../README.md) · [中文配置指南](themes.zh-CN.md)

`Order` arranges prompt segments; `Modules` configures each segment. User and host have separate foreground/background colors. Custom text segments provide separators, arrows, spaces, and labels without executing scripts.

```powershell
upwsh theme list
upwsh theme install "Glacier"
upwsh theme install "iWonder"
```

`list` marks the active theme with `*`. `install` selects an existing local theme, not a download. Editing the selected theme requires running the same selection command again. The next prompt uses the new data; another session's selection does not redraw an idle input line.

## Bundled themes

| Theme | Appearance | Terminal background |
| --- | --- | --- |
| [iWonder](../src/themes/iWonder.json) | Original green/yellow/cyan palette, italic folder, `❯` | Dark |
| [Glacier](../src/themes/Glacier.json) | Ice-blue folder, lavender branch | Dark |
| [Ember](../src/themes/Ember.json) | Amber folder, warm-white branch | Dark |
| [Quiet](../src/themes/Quiet.json) | Hides user/host and duration; `>` on success, `!` on failure | Dark |
| [Daylight](../src/themes/Daylight.json) | Deep-blue folder, purple branch | Light |

All five use v2 while retaining their appearance. Their backgrounds default to `transparent`; individual segments can now have colored backgrounds. Terminal font, window opacity, and overall background remain terminal settings.

## Files and upgrading

Themes live in `~/.config/upwsh/themes/`. The optional selection file `custom/theme.json` contains a filename, for example `{"Theme":"Glacier.json"}`. Without it, iWonder is the default. Invalid selections keep the session's last valid theme or fall back to a valid v2 iWonder.

**Only Version 2 is supported.** There is no v1 reader or automatic conversion. `Colors`, `Symbols`, and `Display` no longer exist; changing just the version number is insufficient.

Install/update preserve existing theme files and selection. If an existing bundled filename still has an old header, deployment stops before replacing program files and names the incompatible file. Back up or move the old `themes/` directory outside the installation, without overwriting an existing backup, then update from this repository:

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/update.ps1 --source src
```

Missing v2 presets are installed. Open a new pwsh and select a theme. Rewrite custom themes from a v2 template; a selection referencing a removed custom theme warns and falls back to iWonder. No deployment step overwrites, moves, or converts personal themes. Subsequent updates also add only missing files.

Uninstall removes `themes/`; `--keep-custom` retains the selection file, not the themes. Back up custom themes separately.

## Configuration

Save this as `themes/My Theme.json`, then select `My Theme`:

```json
{
  "Version": 2,
  "Name": "My Theme",
  "Order": ["user", "at", "host", "directory", "symbol", "space"],
  "Modules": {
    "user": { "Foreground": "#FFFFFF", "Background": "#2563EB" },
    "at": { "Type": "text", "Text": "@", "AttachTo": ["user", "host"] },
    "host": { "Foreground": "#FDE68A", "Background": "#334155", "Suffix": " " },
    "directory": { "Foreground": "#EAB308", "Suffix": " " },
    "symbol": {
      "Text": "❯", "Foreground": "#22C55E",
      "Failure": { "Text": "!", "Foreground": "#FCA5A5", "Background": "#7F1D1D" }
    },
    "space": { "Type": "text", "Text": " " }
  }
}
```

`Order` accepts 1–128 names and can repeat a segment. Only listed segments render. `Modules` accepts 1–64 definitions. Built-in identifiers are case-sensitive; custom identifiers start with an ASCII letter, followed by letters, digits, `_`, or `-`, up to 40 characters.

| Common field | Default and meaning |
| --- | --- |
| `Foreground` | `default` (terminal text color), or `#RRGGBB` |
| `Background` | `transparent` (terminal default background), or `#RRGGBB` |
| `Enabled` | `true`; false hides the segment and skips its data lookup |
| `When` | `always`, `success`, or `failure`; defaults to `always`, except `exitCode` defaults to `failure` |
| `Bold`, `Italic` | `false`; terminal/font support affects appearance |
| `Prefix`, `Suffix` | Empty strings; render only with visible content, in that segment's style |
| `_Comment` | Optional documentation, ignored by rendering |

There are no implicit spaces. Use prefix/suffix or a separate text segment. `transparent` explicitly resets the background; it does not inherit the preceding segment or specify alpha opacity. Six-digit colors only; `#RRGGBBAA` is invalid. The renderer resets all styles before command input.

| Built-in segment | Content and settings |
| --- | --- |
| `user` | Username |
| `host` | Lowercase hostname |
| `directory` | `Style: "folder"` (default) or `"path"` (Unix-style path); home is `~` |
| `git` | Branch; hidden outside filesystem repositories or if lookup fails |
| `duration` | Positive elapsed time at or above `MinMs`; default 2000, integer range 0–86400000 |
| `exitCode` | Failure code by default; missing/zero effective failure code becomes 1. Explicit `When: "always"` shows 0 on success |
| `symbol` | `Text` defaults to `❯`; `Failure` can override `Text`, `Foreground`, `Background`, `Bold`, `Italic` |

Visibility conditions combine: `duration.When: "failure"` means failed **and** above the duration threshold. `Failure` inherits unspecified properties from the normal symbol. Git is queried only if requested and visible; repeated references query once per render.

## Text and conditional connectors

Custom definitions require `Type: "text"` and `Text`. They are literal text, with no interpolation or execution.

`AttachTo` is an optional array of built-in segment names in `Order`. The text renders only when **all** targets are visible. The default `[]` renders independently. Targets cannot be other text segments, preventing dependency cycles.

For example, arrange `timeOpen`, `duration`, `timeClose` consecutively:

```json
"timeOpen":  { "Type": "text", "Text": "[", "AttachTo": ["duration"] },
"duration":  { "Foreground": "#73DACA", "MinMs": 2000 },
"timeClose": { "Type": "text", "Text": "] ", "AttachTo": ["duration"] }
```

These are object entries, not a complete theme. Both brackets disappear with the duration. Use `duration.Prefix`/`Suffix` instead if the brackets share its color.

Text segments also support `previous.background` and `next.background` as foreground/background values. They resolve to the nearest **visible built-in segment** before or after that position, skipping hidden segments and other text. Repeated connectors resolve at each occurrence. Missing neighbors fall back to terminal defaults. A transparent background reference used as foreground becomes `default`, since the terminal's actual background RGB is unknown.

For a Powerline arrow after Git:

```json
"gitArrow": {
  "Type": "text", "Text": "", "AttachTo": ["git"],
  "Foreground": "previous.background",
  "Background": "next.background"
}
```

Place it immediately after `git` in `Order`. Give each conditional data segment its own attached trailing arrow. When Git, duration, or exit code disappears, its arrow disappears too; the previous visible segment's arrow resolves against the next visible background. The [Chinese guide](themes.zh-CN.md#箭头自动连接可见段) has a full layout example.

Two consecutive text segments, such as `` and ``, can form a triangle/notch combination. Set their colors and attachment targets separately; they do not become each other's color neighbors. Terminal cells cannot overlap. Use a font with the required Powerline glyphs and inspect alignment in your terminal.

## Validation and development

Bundled `_Comment` objects explain fields in Chinese. Edit `Modules`, not the comments. Unknown settings fail validation to catch typos. Use standard JSON: quoted strings, unquoted booleans, no trailing commas or `//` comments. Single-line text values allow spaces, but no control characters or line separators, up to 128 UTF-16 code units each. Files are limited to 64 KiB.

Theme names start with a letter/digit, allow letters, digits, spaces, `_`, `-`, and have at most 80 characters with no trailing spaces. CLI names cannot contain paths or `.json` extensions.

`src/theme.psm1` validates and supplies defaults. `src/prompt.psm1` resolves visible data before decorations. The CLI targets the installed directory; directly loading `src/profile.ps1` uses source-local themes. Existing idle prompt caching and selection revision tracking remain unchanged.

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_theme.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt_renderer.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt_segments.ps1
```
