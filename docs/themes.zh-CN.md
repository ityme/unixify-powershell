# 本地主题

[README](../README.zh-CN.md) · [English](themes.md)

默认主题 **iWonder** 保留原有外观。主题只控制提示符，不运行脚本，也不调用 Starship。

## 选择主题

```powershell
upwsh theme list                 # * 标记当前主题
upwsh theme install "Glacier"    # 选择已有的本地主题，不下载
upwsh theme install "iWonder"    # 恢复默认外观
```

| 主题 | 外观 | 建议终端背景 |
| --- | --- | --- |
| [iWonder](../src/themes/iWonder.json) | 绿、黄、青配色，目录斜体，提示字符 `❯` | 深色 |
| [Glacier](../src/themes/Glacier.json) | 冰蓝目录、淡紫分支，不用斜体 | 深色 |
| [Ember](../src/themes/Ember.json) | 琥珀目录、暖白分支，不用斜体 | 深色 |
| [Quiet](../src/themes/Quiet.json) | 中性色；隐藏用户名和耗时；成功 `>`，失败 `!` | 深色 |
| [Daylight](../src/themes/Daylight.json) | 深蓝目录、深紫分支，不用斜体 | 浅色 |

五组都显示当前文件夹、Git 分支和失败退出码。除 Quiet 外，都显示用户名和主机名，耗时达到 2 秒时显示执行时间。

**主题只改文字前景色。** 背景、字体、字号由 WezTerm 或 Windows Terminal 控制；选择 Daylight 不会自动切成浅色背景。

在已加载主题功能的会话中，切换后下一次提示符生效，无需重启。在另一个窗口或通过 `upwsh.cmd` 切换时，本窗口会在下次生成提示符时读取选择，不会在空闲输入过程中自行重绘。

## 配置文件在哪里

```text
~/.config/upwsh/
  themes/
    iWonder.json
    Glacier.json
    Ember.json
    Quiet.json
    Daylight.json
  custom/
    theme.json
```

`themes/名称.json` 保存外观配置。`custom/theme.json` 只记录选择：

```json
{"Theme":"Glacier.json"}
```

没有选择文件时默认使用 iWonder，这是正常状态。选择无效主题时，命令报错并保留原选择；选择文件损坏时，已有会话保留上次可用主题，新会话回退到 iWonder。

安装或更新会补齐缺失的主题，**不会覆盖同名文件或改变主题选择**。因此，旧版 iWonder 文件不会自动加上新注释；可查看上表链接中的带注释版本，不必覆盖自己的修改。卸载会删除 `themes/`；`--keep-custom` 只保留选择文件，不保留主题文件，卸载前请另行备份自定义主题。

## 自定义一份主题

在 PowerShell 中复制已安装的模板：

```powershell
Copy-Item "$HOME/.config/upwsh/themes/iWonder.json" "$HOME/.config/upwsh/themes/My Theme.json"
notepad "$HOME/.config/upwsh/themes/My Theme.json"
```

1. 将 `Name` 改为 `My Theme`，与文件名一致，不含 `.json`。
2. 修改实际的 `Colors`、`Symbols` 和 `Display` 值。
3. 保存文件，再执行：

```powershell
upwsh theme install "My Theme"
```

**修改已选中的主题后，也要再执行一次这条命令。** 程序会重新读取 JSON；平时缓存解析结果，只检查小型选择文件的时间戳和大小，不在每次按键时解析主题。

每个模板末尾的 `_Comment` 都有中文字段说明。它是合法 JSON 元数据，不参与渲染，可保留或删除。修改 `_Comment` 中的文字不会改变外观。使用标准 JSON：字符串加双引号，布尔值写 `true` 或 `false`，不要加引号、尾逗号或 `//` 注释。

## 字段说明

| 字段 | 怎么配置 |
| --- | --- |
| `Version` | 格式版本，保持整数 `1` |
| `Name` | 与文件名一致，不含 `.json` |
| `Colors.UserHost` | 用户名和主机名颜色 |
| `Colors.Directory` | 目录颜色 |
| `Colors.Branch` | Git 分支颜色 |
| `Colors.Duration` | 耗时颜色 |
| `Colors.Success` | 成功提示字符颜色 |
| `Colors.Error` | 失败退出码和提示字符颜色 |
| `Symbols.Success` | 成功提示字符，例如 `❯` 或 `>` |
| `Symbols.Error` | 失败提示字符，例如 `❯` 或 `!` |
| `Display.ShowUserHost` | 是否显示 `用户名@主机名` |
| `Display.ShowGitBranch` | 是否显示分支；`false` 同时跳过渲染时的分支查询 |
| `Display.ShowDuration` | 是否显示达到门槛的耗时 |
| `Display.ShowExitCode` | 是否在失败时显示数字退出码 |
| `Display.DirectoryStyle` | `folder` 只显示末级目录，`path` 显示 Unix 风格路径；家目录显示 `~` |
| `Display.DirectoryItalic` | 目录是否斜体，需要终端和字体支持 |
| `Display.SymbolBold` | 成功或失败提示字符是否加粗 |
| `Display.ErrorBold` | 失败退出码是否加粗 |
| `Display.DurationMinMs` | 耗时门槛，整数毫秒，范围 `0`–`86400000`；`2000` 为 2 秒 |
| `_Comment` | 可选说明，不是配置项 |

颜色必须写成 `#RRGGBB`，例如 `#8CC8FF`。提示字符长度为 1–16 个 UTF-16 代码单元，不能包含空白或终端控制字符。主题名以字母或数字开头，支持字母、数字、空格、下划线、短横线，最多 80 个字符，末尾不能有空格。命令中的名称不能包含路径或 `.json` 后缀。

除 `_Comment` 外，模板里的配置项都必须保留。建议复制模板再改，文件不超过 64 KiB。

## 更新本地源码中的主题

在本项目根目录执行：

```powershell
pwsh -NoLogo -NoProfile -File src/scripts/update.ps1 --source src
```

更新后新开 pwsh，再执行 `upwsh theme list`。还没安装时，使用 `src/scripts/install.ps1`。

注意：命令行管理的是 `~/.config/upwsh/themes/`，不是仓库的 `src/themes/`。只修改仓库文件，不会改变已安装的同名主题；开发时直接加载 `src/profile.ps1` 才使用源码目录中的主题数据。
