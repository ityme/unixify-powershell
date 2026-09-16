# unixify-powershell

PowerShell 7 的 Unix 风格命令、补全和 profile。需要 `pwsh`。

## 安装

下载运行时到 `~/.config/upwsh`，写入当前用户的 pwsh profile（`$PROFILE.CurrentUserAllHosts`）。Windows，需要 PowerShell 7。

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.ps1 | iex
```

指定项目根用 `UPWSH_HOME`（默认 `~/.config/upwsh`）。CLI 装在 `$UPWSH_HOME\bin`，安装时写入用户 PATH。

```powershell
$env:UPWSH_HOME = "$HOME\.config\upwsh"
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.ps1 | iex
```

管道安装也可以用 `UPWSH_REF`、`UPWSH_REPO`。

装完开一个新的 `pwsh`。`upwsh --help` 能跑就对了。

```powershell
upwsh --help
```

选项见 `src/scripts/bootstrap.ps1 --help`。

## 用

profile 加载后直接跑 `upwsh`。没加载时用部署出来的脚本：

```powershell
pwsh -NoLogo -NoProfile -File $HOME/.config/upwsh/scripts/upwsh.ps1 --help
```

| 命令 | 作用 |
| --- | --- |
| `upwsh load` | 挂钩当前这份运行时 |
| `upwsh unload` | 去掉挂钩，不删文件 |
| `upwsh tool list` | 列出支持的 CLI |
| `upwsh tool install` | 安装常用 CLI |
| `upwsh tool install eza rg` | 只装点名的 CLI |
| `upwsh tool uninstall eza` | 删掉点名的 CLI |

二级选项见 `upwsh --help`。

## 从仓库装

```powershell
git clone https://github.com/ityme/unixify-powershell.git
cd unixify-powershell
pwsh -NoLogo -NoProfile -File src/scripts/bootstrap.ps1
```

旁边有源码时，`src/scripts/bootstrap.ps1` 不再下载，把 `src/` 拷到 `~/.config/upwsh`。

只挂钩这份源码、不拷文件：

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 load
```

## 卸载

```powershell
upwsh unload
```

或：

```powershell
pwsh -NoLogo -NoProfile -File $HOME/.config/upwsh/scripts/upwsh.ps1 unload
```

`~/.config/upwsh` 还在，要删自己删。

## 开发

`src/` 是源码树。

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install.ps1
```
