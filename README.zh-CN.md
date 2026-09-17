# unixify-powershell

Windows 上 Unix 风格的 PowerShell 7：路径、命令、补全。

[English](README.md) | [简体中文](README.zh-CN.md)

## 使用前 / 使用后

原生 pwsh 是 Windows 路径和 cmdlet。`load` 之后，路径和命令按 Unix 写，Tab 补全也是 Unix 形式。真正执行时才转回 Windows 路径。

| 之前 | 之后 |
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

## 安装

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

拷到 `~/.config/upwsh`，再加载进 pwsh。

安装目录固定为 `~/.config/upwsh`。`UPWSH_HOME` 只记录这个路径，修改它不会改变安装位置。

在本项目或其子目录中运行 `upwsh install`，使用本地 `src/`；在项目外运行则下载源码。可用 `--source`、`--ref`、`--repo` 指定来源；管道安装对应使用 `UPWSH_SOURCE`、`UPWSH_REF`、`UPWSH_REPO`。

开一个新的 `pwsh`。`upwsh --help` 能跑即可。

## 命令

`load` 之后，当前这个 pwsh 里有 `ll`、`cd`、补全和 `upwsh`。以后新开的 pwsh 从 `$PROFILE` 同样加载。Path 上的 `upwsh` 是 `%UPWSH_HOME%\bin\upwsh.cmd`。

| 命令 | 作用 |
| --- | --- |
| `upwsh install` | 从本地项目或网络安装到 `~/.config/upwsh`，然后加载 |
| `upwsh update` | 按相同来源规则重新安装到 `~/.config/upwsh`，保留 `custom/` |
| `upwsh uninstall` | 删除自动加载配置、相关 Path 项、`UPWSH_HOME` 和 `~/.config/upwsh` |
| `upwsh load` | 将 `~/.config/upwsh/profile.ps1` 加载进 pwsh，并设置启动时自动加载 |
| `upwsh unload` | `$PROFILE` 不再加载。文件、Path、`upwsh` 命令还在 |
| `upwsh tool list` | 列出 CLI，并看 Path 上有没有 |
| `upwsh tool install [names…]` | 把 CLI 装进 `tool\bin` |
| `upwsh tool uninstall <names…>` | 删掉点名的 CLI |

`load` 还会写用户环境变量 `UPWSH_HOME`，并把 `%UPWSH_HOME%\bin`、`%UPWSH_HOME%\tool\bin` 接到用户 Path 末尾。必须先 `install`，`load` 不再加载源码目录。`unload` 停止以后自动加载，不撤销当前会话中已加载的功能。

个人文件：`$UPWSH_HOME\custom\*.ps1`。样板在 `custom\alias.ps1`（`w`、`t`、`i`、`d`、`gs`）。`update` 会保留这个目录。

## 目录

```
~/.config/upwsh/
  profile.ps1
  scripts/
  bin/upwsh.cmd      # upwsh 命令
  tool/bin/          # eza、rg 等
  custom/alias.ps1   # 样板快捷方式（w、t、i、d、gs）
```

## 从仓库装

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/install.ps1
```

如果已经装过 `upwsh`，在本仓库运行 `upwsh install` 即可安装本地改动。两种方式都会把 `src/` 拷到 `~/.config/upwsh`，不会把仓库当作安装目录。

## 更新

```powershell
upwsh update
```

## 卸载

```powershell
upwsh uninstall
```

`$PROFILE` 不再加载（文件和 Path 留下）：

```powershell
upwsh unload
```

不会删 git 仓库。

## 提示符性能

空回车复用上一次提示符；执行命令、切换目录或改变窗口宽度后刷新。保留 Starship 样式，Git 状态、时间等动态内容在执行命令后刷新，空回车不重新计算。

在 Windows 上测量空回车耗时（p95 目标：30ms）：

```powershell
pwsh -NoLogo -NoProfile -File src/tests/bench_prompt.ps1 -Enforce
python src/tests/bench_console.py --enforce
```

第一条测提示符执行路径；第二条通过 Windows ConPTY 发送真实回车。启动和首次提示符耗时单独列出，不包含终端程序绘制到屏幕的时间。

## 测试

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
