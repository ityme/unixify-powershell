# Development

[README](../README.md) · [中文介绍](../README.zh-CN.md)

`src/` contains the runtime; lifecycle entry points are in `src/scripts/`. Installation copies the runtime to `~/.config/upwsh` and excludes `src/tests/`.

## Tests

Run from the repository root with PowerShell 7:

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_path_commands.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_git_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_interaction.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```

The test harness uses temporary user homes and profiles and disables persistent environment writes.

## Git completion

`src/git_completion.psm1` handles common Git command positions before filesystem completion. It reads refs and configured remotes only when requested by Tab, without contacting a remote. Each query has a 500ms process wait limit and leaves `$LASTEXITCODE` unchanged. Subcommand names need no Git process. The scope is intentionally limited; unknown syntax returns to normal completion.

Git completion tests create and remove an isolated local repository with fixture branches, tags, and remote-tracking refs. They do not modify the project repository or access remotes.

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
pwsh -NoLogo -NoProfile -File src/tests/bench_interaction.ps1 -Files 1000 -Samples 10
```

- `bench_prompt.ps1` measures profile loading, the first prompt, and empty Enter handling.
- `bench_console.py` sends Enter through Windows ConPTY. It requires Python and uses only the standard library.
- `bench_interaction.ps1` measures terminal reporting and file completion with generated files.

The empty Enter target is p95 below 30ms. Startup and completion have separate measurements; ConPTY timings exclude the terminal application's screen painting. Compare repeated runs on the same machine, since system load affects the results.

Empty Enter reuses the previous prompt. Commands, directory changes, and window width changes refresh it. With Starship, Git status, time, and other dynamic segments therefore refresh after a command, not on empty Enter.

Explicit path completion queries the filesystem first. Candidate display reuses that keypress's results; the next Tab queries again to see filesystem changes. Idle terminal reports reuse encoded text until the directory, virtual environment, result, or enabled fields change.
