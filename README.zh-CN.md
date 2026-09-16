# unixify-powershell

PowerShell 7 的 Unix 风格命令、补全和 profile。仅 Windows，需要 `pwsh`。

[English](README.md) | [简体中文](README.zh-CN.md)

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

个人文件：`$UPWSH_HOME\custom\*.ps1`（默认空）。`update` 会保留这个目录。

## 目录

```
~/.config/upwsh/
  profile.ps1
  scripts/
  bin/upwsh.cmd      # upwsh 命令
  tool/bin/          # eza、rg 等
  custom/            # 你的配置
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
