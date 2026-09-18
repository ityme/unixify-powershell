# Development

[README](../README.md) · [中文介绍](../README.zh-CN.md)

`src/` contains the runtime; lifecycle entry points are in `src/scripts/`. Installation copies the runtime to `~/.config/upwsh` and excludes `src/tests/`.

## Tests

Run from the repository root with PowerShell 7:

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_path_commands.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_git_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_git_cache.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_interaction.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_deploy_locks.ps1
```

The test harness uses temporary user homes and profiles and disables persistent environment writes.

## Deployment

Install/update validate staged files before changing the installation. They keep live directories in place because Windows directory handles can prevent whole-tree renames. Changed program files use same-volume file replacement with a backup journal; unchanged files, tools, and existing custom settings are left in place. Missing custom templates are added and journaled.

A caught deployment error restores completed file changes, the profile, and environment settings. A locked program file causes a failure naming that file; the installer does not kill the owning process or require elevation. If rollback itself fails, recovery files remain and their locations are reported. Replacement is atomic per file, not across the entire installation; process termination or power loss is outside this rollback guarantee. Open a new pwsh after a successful update.

The lock tests use temporary installations and Windows handles that deny rename/delete, including locked tool and custom files.

## Git completion

`src/git_completion.psm1` handles common Git command positions before filesystem completion. It reads refs and configured remotes only when requested by Tab, without contacting a remote. Each query has a 500ms process wait limit and leaves `$LASTEXITCODE` unchanged. Subcommand names need no Git process. The scope is intentionally limited; unknown syntax returns to normal completion.

Successful raw queries are cached for 1 second, capped at 16 entries with oldest-entry eviction. Keys include the working directory, executable, ordered `-C` and query arguments, and Git environment overrides. Actual command input clears query data; empty Enter does not. Failed or timed-out queries are not cached. Git executable discovery is reused until Path, PATHEXT, working directory, or executable availability changes.

Git completion tests create and remove isolated local repositories with fixture branches, tags, and remote-tracking refs. Cache tests use Git Trace2 to count real queries. They do not modify the project repository or access remotes.

## Path conversion

`src/path_convert.ps1` defines `winpath` and `unixpath`. Interactive input, completion, command output, and setup share these interfaces. The Enter handler decides which arguments to convert; the converter functions only transform path text.

Standalone installers contain generated copies so `irm | iex` works before installation. After editing the converter, synchronize and check those copies:

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/sync_path_convert.ps1
pwsh -NoLogo -NoProfile -File src/scripts/sync_path_convert.ps1 -Check
```

## Performance

```powershell
pwsh -NoLogo -NoProfile -File src/tests/bench_prompt.ps1 -Enforce
python src/tests/bench_console.py --enforce
python src/tests/bench_console.py --completion --samples 20
python src/tests/bench_console.py --lifecycle
pwsh -NoLogo -NoProfile -File src/tests/bench_interaction.ps1 -Files 1000 -Samples 10
pwsh -NoLogo -NoProfile -File src/tests/bench_git_completion.ps1 -Samples 20
```

- `bench_prompt.ps1` measures profile loading, the first prompt, and empty Enter handling.
- `bench_console.py` sends Enter through Windows ConPTY. `--completion` creates a temporary Git repository, types `git pull origin `, and presses Tab without executing the command. It checks that listing candidates preserves the buffer and does not rerun the prompt renderer or emit prompt-boundary events. `--lifecycle` checks actual Ctrl+L/Ctrl+C, multiline cancellation, alternate submission, failure, and interruption behavior. It requires Python and uses only the standard library.
- `bench_interaction.ps1` measures terminal reporting and file completion with generated files.
- `bench_git_completion.ps1` compares fresh queries with immediate repeats in the current repository, including word completion and its trailing space. The first query still starts Git; different query types do not share cache entries.

The empty Enter target is p95 below 30ms. Startup and completion have separate measurements; ConPTY timings exclude the terminal application's screen painting. Compare repeated runs on the same machine, since system load affects the results.

`PSConsoleHostReadLine` records submitted code after PSReadLine returns, independent of the submit key. Empty/comment-only input and editing cancellation leave the cached prompt valid. A pending command is consumed once by the next prompt, including failure or execution interruption. While PSReadLine is editing, prompt redraws do not emit command-finished or prompt-boundary events. Idle new input lines emit prompt boundaries but no false command completion. End time is captured before rendering, and the last success/exit snapshot survives idle redraws.

Directory and window-width changes also invalidate the rendered text. With Starship, branch/status/time changes made elsewhere are not polled: they appear after a command in this shell. This snapshot policy deliberately favors predictable low-latency editing.

Explicit path completion queries the filesystem first. Candidate display reuses that keypress's results; the next Tab queries again to see filesystem changes. Idle terminal reports reuse encoded text until the directory, virtual environment, result, or enabled fields change.
