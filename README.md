# PowerShell 配置

独立于 WezTerm。WezTerm 只在该 profile 存在时选用它。统一入口是 `upwsh`：

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 --help
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 --reload
pwsh -NoLogo -NoProfile -File src/scripts/upwsh.ps1 --install --check
```

profile 加载后也可直接跑 `upwsh --help`。`--reload` / `-r` 挂钩当前用户的 pwsh（默认 `$PROFILE.CurrentUserAllHosts`，指向本仓库 `src/profile.ps1`）。`--install` / `-i` 安装常用 CLI。二级选项见 `upwsh --help`。

`src/` 是源码树。发版去掉 `src/tests/`，其余部署到 `$HOME\.config\pwsh`。

验证：

```powershell
pwsh -NoLogo -NoProfile -File src/tests/test_completion.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_install_profile.ps1
pwsh -NoLogo -NoProfile -File src/tests/test_upwsh.ps1
```
