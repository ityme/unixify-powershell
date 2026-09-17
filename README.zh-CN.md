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

家目录：`$env:UPWSH_HOME`，否则用户环境变量 `UPWSH_HOME`，否则 `~/.config/upwsh`。

```powershell
$env:UPWSH_HOME = "$HOME\.config\upwsh"
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/install.ps1 | iex
```

管道还可用 `UPWSH_REF`、`UPWSH_REPO`。旁边有这份仓库时，`install.ps1` 直接拷 `src/`，不下载。

开一个新的 `pwsh`。`upwsh --help` 能跑即可。

## 命令

`load` 之后，当前这个 pwsh 里有 `ll`、`cd`、补全和 `upwsh`。以后新开的 pwsh 从 `$PROFILE` 同样加载。Path 上的 `upwsh` 是 `%UPWSH_HOME%\bin\upwsh.cmd`。

| 命令 | 作用 |
| --- | --- |
| `upwsh install` | 拷到家目录，再 load |
| `upwsh update` | 卸载但保留 `custom`，再安装 |
| `upwsh uninstall` | unload，再删 `UPWSH_HOME`、Path 和安装目录 |
| `upwsh load` | 加载进当前 pwsh，并写入 `$PROFILE`，以后新开的 pwsh 也会加载 |
| `upwsh unload` | `$PROFILE` 不再加载。文件、Path、`upwsh` 命令还在 |
| `upwsh tool list` | 列出 CLI，并看 Path 上有没有 |
| `upwsh tool install [names…]` | 把 CLI 装进 `tool\bin` |
| `upwsh tool uninstall <names…>` | 删掉点名的 CLI |

`load` 还会写用户环境变量 `UPWSH_HOME`，并把 `%UPWSH_HOME%\bin`、`%UPWSH_HOME%\tool\bin` 接到用户 Path 末尾。

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

把这份源码加载进 pwsh，不拷文件：

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 load
```

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

## 测试

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
