# unixify-powershell

PowerShell 7 的 Unix 风格命令、补全和 profile。Windows，需要 `pwsh`。

## 安装

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

默认拷到 `~/.config/upwsh`（`$HOME\.config\upwsh`），再 `upwsh load`。

指定家目录：

```powershell
$env:UPWSH_HOME = "$HOME\.config\upwsh"
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

管道还可以用 `UPWSH_REF`、`UPWSH_REPO`。旁边有这份源码时，`install.ps1` 不再下载，把 `src/` 拷进家目录。

装完新开一个 `pwsh`，`upwsh --help` 能跑就对了。

选项见 `src/scripts/install.ps1 --help`。

## 命令

profile 加载后直接跑 `upwsh`。没加载时：

```powershell
pwsh -NoLogo -NoProfile -File $HOME/.config/upwsh/scripts/upwsh.ps1 --help
```

或用 Path 上的 `%UPWSH_HOME%\bin\upwsh.cmd`。

| 命令 | 作用 |
| --- | --- |
| `upwsh install` | 拷运行时到家目录并 `load` |
| `upwsh update` | `uninstall --keep-custom`，再 `install` |
| `upwsh uninstall` | `unload`，再删 `UPWSH_HOME`、Path 和安装树 |
| `upwsh load` | 挂钩 profile，写 `UPWSH_HOME` 和 Path，当前 pwsh 立刻生效 |
| `upwsh unload` | 去掉挂钩；`UPWSH_HOME` 和 Path 仍在，`upwsh` 还能跑 |
| `upwsh tool list` | 列出支持的 CLI，并看 shell 里有没有 |
| `upwsh tool install` | 安装常用 CLI 到 `tool\bin` |
| `upwsh tool install eza rg` | 只装点名的 CLI |
| `upwsh tool uninstall eza` | 删掉点名的 CLI |

`install` / `uninstall` / `update` 转给 `scripts\` 里同名脚本。从安装树用 `upwsh uninstall` 或 `upwsh update` 时，会拷到临时目录另起进程再删，避免 `upwsh.cmd` 占着文件。

个人别名放 `$UPWSH_HOME\custom\*.ps1`（默认空）。`update` 和 `uninstall --keep-custom` 会留下这个目录。

二级选项见 `upwsh --help`。

## 家目录

默认 `~/.config/upwsh`。`$env:UPWSH_HOME` 优先，否则用用户环境变量，再否则用这个默认。

```
~/.config/upwsh/
  profile.ps1
  alias.ps1
  *.psm1
  upwsh_home.ps1
  scripts/          install / uninstall / update / upwsh
  bin/upwsh.cmd     Path 上的 upwsh 命令
  tool/bin/         eza、rg 等
  custom/           个人 overlay，默认空
```

`install` 不拷 `src/tests`。`load` 写出 `bin\upwsh.cmd`，并把 `%UPWSH_HOME%\bin`、`%UPWSH_HOME%\tool\bin` 接到用户 Path 末尾。

## 从仓库装

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/install.ps1
```

只挂钩这份源码、不拷文件：

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 load
```

## 更新

```powershell
upwsh update
```

或：

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/update.ps1 | iex
```

先 `uninstall --keep-custom`，再 `install`。`custom\` 还在。

## 卸载

只去掉挂钩，命令和环境还在：

```powershell
upwsh unload
```

拆干净（挂钩、`UPWSH_HOME`、Path、安装树）：

```powershell
upwsh uninstall
```

或：

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/uninstall.ps1 | iex
```

git 仓库不会删。`--keep-custom` 会留下 `custom\`。

## 开发

`src/` 是源码树。

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
