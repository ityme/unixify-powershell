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

## 路径

交互输入中，独立且**未加引号**的 `/c/...`、`~/...` 参数会在执行前转换。带引号的文本、注释、内嵌脚本、重定向和 `--output=/c/a` 这类组合参数保持原文。管道和复合命令逐个参数处理，不按命令名特殊适配。

含空格的路径、变量和脚本中的路径，用显式转换：

```powershell
winpath '/c/my work'          # C:/my work
unixpath 'C:\my work'         # /c/my work
cd (winpath '~/my work')
'C:\one', 'D:\two' | unixpath
```

两条命令都支持多个路径和管道输入，不要求路径存在，不展开通配符。`C:relative` 保留盘符相对路径含义。PowerShell 和被调用程序自身的参数语义不变。

Tab 补全遇到需要引号的 Unix 绝对路径时，会生成 `(winpath '…')`。脚本和 custom 函数内也应显式使用 `winpath`；回车转换只作用于交互输入。

## 安装

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

安装到 `~/.config/upwsh`，首次安装自动启用。新开 pwsh 后生效。

安装目录固定为 `~/.config/upwsh`。`UPWSH_HOME` 只记录这个路径，修改它不会改变安装位置。

在本项目或其子目录中运行 `upwsh install`，使用本地 `src/`；在项目外运行则下载源码。可用 `--source`、`--ref`、`--repo` 指定来源；管道安装对应使用 `UPWSH_SOURCE`、`UPWSH_REF`、`UPWSH_REPO`。

开一个新的 `pwsh`。`upwsh --help` 能跑即可。

## 命令

启用后，pwsh 启动时加载 `ll`、`cd`、补全和 `upwsh`。Path 上的命令是 `%UPWSH_HOME%\bin\upwsh.cmd`。

| 命令 | 作用 |
| --- | --- |
| `upwsh install` | 安装或修复 `~/.config/upwsh`；首次安装自动启用 |
| `upwsh update` | 更新已有安装，保留个人配置、工具和启用/停用状态 |
| `upwsh uninstall` | 删除自动加载配置、相关 Path 项、`UPWSH_HOME` 和 `~/.config/upwsh` |
| `upwsh load` | 启用启动时自动加载；通过 pwsh 函数调用时，也加载当前会话 |
| `upwsh unload` | `$PROFILE` 不再加载。文件、Path、`upwsh` 命令还在 |
| `upwsh tool list` | 列出 CLI，并看 Path 上有没有 |
| `upwsh tool install [names…]` | 把 CLI 装进 `tool\bin` |
| `upwsh tool uninstall <names…>` | 删掉点名的 CLI |

`install` 管理 `UPWSH_HOME`、用户 Path 中的 `%UPWSH_HOME%\bin` / `%UPWSH_HOME%\tool\bin` 和命令垫片。`load` / `unload` 只管理自动加载。通过 `upwsh.cmd` 或 `pwsh -File` 调用时，`load` 无法修改父会话，需要新开 pwsh；`unload` 不撤销当前会话中已加载的功能。

个人文件：`$UPWSH_HOME\custom\*.ps1`。样板在 `custom\alias.ps1`（`w`、`t`、`i`、`d`、`gs`）。重复安装和更新都会保留这个目录及已安装的工具。

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

安装和更新先准备并校验新版本，再替换程序；部署失败会恢复原来的文件和配置。`update` 要求已经安装，停用状态也会保留。安装或更新后，新开 pwsh 使用新代码。

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

分别测量终端上报和文件补全：

```powershell
pwsh -NoLogo -NoProfile -File src/tests/bench_interaction.ps1 -Files 1000 -Samples 10
```

明确路径优先查询文件系统，展示候选时复用本次查询结果；下一次 Tab 仍重新查询，确保文件变化可见。空闲终端上报复用已编码文本，目录、虚拟环境、执行结果或启用字段变化后重新生成。

## 开发

路径格式转换统一使用 `src/path_convert.ps1` 中的 `winpath`、`unixpath`。交互改写、补全、命令输出和安装管理共用这两个接口。独立安装脚本内嵌自动生成的副本，保证尚未安装时也能用 `irm | iex`。

修改转换逻辑后，同步并检查副本：

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/sync_path_convert.ps1
pwsh -NoLogo -NoProfile -File src/scripts/sync_path_convert.ps1 -Check
```

## 测试

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_path_commands.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_prompt.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_interaction.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
