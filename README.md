# unixify-powershell

PowerShell 7 的 Unix 风格命令、补全和 profile。需要 `pwsh`。

## 安装

下载运行时到 `~/.config/upwsh`，写入当前用户的 pwsh profile（`$PROFILE.CurrentUserAllHosts`）。Windows，需要 PowerShell 7。

```powershell
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.ps1 | iex
```

指定目录用 `UPWSH_DIR`：

```powershell
$env:UPWSH_DIR = "$HOME\.config\upwsh"
irm https://raw.githubusercontent.com/ityme/unixify-powershell/main/src/scripts/bootstrap.ps1 | iex
```

管道安装也可以用 `UPWSH_REF`、`UPWSH_REPO`。

装完开一个新的 `pwsh`。`upwsh --help` 能跑就对了。

```powershell
upwsh --load --check
```

选项见 `src/scripts/bootstrap.ps1 --help`。

## 用

profile 加载后直接跑 `upwsh`。没加载时用部署出来的脚本：

```powershell
pwsh -NoLogo -NoProfile -File $HOME/.config/upwsh/scripts/upwsh.ps1 --help
```

| 命令 | 作用 |
| --- | --- |
| `upwsh --load --check` | 看 profile 有没有挂钩 |
| `upwsh --load` | 挂钩当前这份运行时 |
| `upwsh --load --deploy` | 拷到 `~/.config/upwsh`，挂钩副本 |
| `upwsh --load --uninstall` | 去掉挂钩，不删文件 |
| `upwsh --install --check` | 看 bat、eza、rg 等 CLI |
| `upwsh --install` | 安装常用 CLI |

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
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 --load
```

## 卸载

```powershell
upwsh --load --uninstall
```

或：

```powershell
pwsh -NoLogo -NoProfile -File $HOME/.config/upwsh/scripts/upwsh.ps1 --load --uninstall
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
