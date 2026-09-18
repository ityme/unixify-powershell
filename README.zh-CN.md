# unixify-powershell

为 **Windows 上的 PowerShell 7** 提供 Unix 风格的路径、命令和 Tab 补全。

[English](README.md)

用 `/c/Users`、`~/projects` 表示路径，用 `ls`、`cp -r`、`grep` 等熟悉的命令操作文件，Tab 也补全为正斜杠路径。语法和管道仍使用 PowerShell。

| 操作 | 原生 PowerShell | 使用 unixify-powershell |
| --- | --- | --- |
| 切换目录 | `cd I:\ispace` | `cd /i/ispace` |
| 列出文件 | `Get-ChildItem` | `ls` / `ll`（通过 eza） |
| 复制目录 | `Copy-Item -Recurse src backup` | `cp -r src backup` |
| 搜索文件内容 | `Select-String error app.log` | `grep error app.log` |
| Tab 补全路径 | `I:\ispace\project\` | `/i/ispace/project/` |

## 安装

在 PowerShell 7（`pwsh`）中执行：

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

安装位置为 `~/.config/upwsh`，首次安装会设置 PowerShell 启动时自动加载。**新开一个 pwsh**，再安装 `ls`、`ll`、`tree` 所需的 eza：

```powershell
upwsh tool install eza
```

## 使用路径

交互输入时，用小写盘符前缀和正斜杠表示路径：

```powershell
cd /i/ispace
cd ~/Desktop
cd -                         # 返回上一个目录
```

独立、未加引号的 `/c/...`、`~/...` 参数会在执行前转为 Windows 路径。引号内的文本保持原样，例如 `'use /c/demo'` 不会被改写。

含空格的路径、变量或脚本中的路径，用 `winpath` 显式转换；反向转换用 `unixpath`：

```powershell
winpath '/c/my work'          # C:/my work
unixpath 'C:\my work'         # /c/my work
cd (winpath '~/my work')
'C:\one', 'D:\two' | unixpath
```

两条命令都支持多个路径和管道输入，不要求路径存在。Tab 遇到需要引号的 Unix 绝对路径时，会生成 `(winpath '…')`。注释、内嵌脚本、重定向和 `--output=/c/a` 这类组合参数不会自动转换。

## Git 补全

Git 在 Path 上时，按 Tab 补全常用子命令、分支、标签和已配置的远程名称：

```text
git sw<Tab>                  → git switch
git switch fe<Tab>           → 匹配的本地分支
git checkout v<Tab>          → 匹配的标签及其他引用
git push o<Tab>              → origin
git pull origin <Tab>        → 本地已知的 origin 分支
git checkout -- ./<Tab>      → 文件
```

只读取本地 Git 数据，不联网、不需要额外依赖。支持 `git -C <目录>` 和 `git switch --track`，其他复杂写法回退到普通补全。

## 管理安装

| 命令 | 作用 |
| --- | --- |
| `upwsh install` | 安装或修复；首次安装自动启用 |
| `upwsh update` | 更新已有安装，保留个人配置、工具和启用/停用状态 |
| `upwsh load` | 启用启动时自动加载 `~/.config/upwsh/profile.ps1` |
| `upwsh unload` | 停止自动加载，保留文件、工具和 `upwsh` 命令 |
| `upwsh uninstall` | 删除安装、自动加载配置及项目添加的环境变量和 Path 项 |

安装或更新后，新开 pwsh 生效。通过已加载的 `upwsh` 函数调用 `load`，还会加载当前会话；`unload` 不撤销当前会话中已加载的功能。卸载时需要保留个人配置，可用 `upwsh uninstall --keep-custom`。

安装目录固定为 `~/.config/upwsh`，`UPWSH_HOME` 记录这个位置。命令帮助见 `upwsh --help`。

## CLI 工具

按需安装到 `~/.config/upwsh/tool/bin`：

```powershell
upwsh tool list
upwsh tool install eza rg fd fzf
upwsh tool uninstall rg
```

## 个人配置

编辑 `~/.config/upwsh/custom/alias.ps1`，修改自带的 `w`、`t`、`i`、`d`、`gs` 快捷命令。也可以添加自己的 `custom/*.ps1` 文件；PowerShell 会在内置配置之后，按文件名顺序加载它们。

例如，在 `custom/work.ps1` 中写入：

```powershell
function global:work { cd (winpath '/i/my work') }
```

重复安装和更新会保留已有文件，并补齐缺失的模板。修改后新开 pwsh 生效。

## 从源码安装

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/install.ps1
```

装好后，在本项目内执行 `upwsh install` 或 `upwsh update`，会使用本地 `src/`；在项目外执行则下载源码。可用 `--source`、`--ref`、`--repo` 指定来源，管道安装对应使用 `UPWSH_SOURCE`、`UPWSH_REF`、`UPWSH_REPO`。

测试、性能测量和路径转换接口维护见[开发说明](docs/development.md)。
