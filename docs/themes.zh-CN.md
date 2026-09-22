# 本地主题（v2）

[README](../README.zh-CN.md) · [English](themes.md)

主题由 **`Order` 排列顺序**和 **`Modules` 分段设置**组成。每段独立设置前景、背景、粗体、斜体及前后文字。自定义段只显示固定文字，不执行 PowerShell。

## 选择主题

```powershell
upwsh theme list                 # * 标记当前主题
upwsh theme use "colorful-blue" # 选择已有的本地主题，不下载
upwsh theme use "pure-default"  # 恢复默认外观
```

[README 主题画廊](../README.zh-CN.md#主题)包含全部 12 套主题的介绍和预览图；下载仓库后用浏览器打开 [themes.html](themes.html)，可离线切换八种命令状态。

- **pure-***：`pure-default`（原 iWonder）、`pure-glacier`、`pure-ember`、`pure-quiet`、`pure-daylight`。透明背景，原有外观不变；Daylight 用于浅色终端背景。
- **colorful-***：`colorful-blue`、`colorful-green`、`colorful-macaron`、`colorful-morandi`、`colorful-cyberpunk`、`colorful-retro`、`colorful-memphis`。用户、主机、目录、Git 使用连续色块；耗时、返回码和提示字符使用透明背景，需要含 Powerline 字形的字体。

主题名称和文件名统一使用小写、短横线。更新会刷新内置文件，不会重命名或删除 `custom/themes/` 中的个人主题。没有旧名称别名。

Colorful 保留参考的背景色，仅修正部分文字对比；每份 JSON 的 `_Comment.ContrastAdjustments` 列出差异。原 OS / Username 两级配色用于 user / host，没有增加时钟或 OS 模块。整体背景和窗口透明度仍由终端控制。

## 文件与生效方式

内置主题位于 `~/.config/upwsh/themes/`，由 unixify-powershell 管理。每次安装或更新都会用 `src/themes/` 中的新版本强制覆盖。个人主题放在 `~/.config/upwsh/custom/themes/`，更新不会覆盖；同名个人主题优先于内置主题。

选择文件位于 `~/.config/upwsh/custom/theme.json`，例如 `{"Theme":"colorful-blue.json"}`。没有选择文件时使用 pure-default。

布局变更后的第一次更新会把直接放在 `themes/` 下、且不属于内置主题的 JSON 移到 `custom/themes/`。如果目标目录已有同名文件，会保留目标文件，并警告旧文件仍在 `themes/`。需要保留两份时，请先备份安装目录。

选择后下一次提示符生效。在另一个窗口或通过 `upwsh.cmd` 切换时，本窗口下次生成提示符才会读取选择，不在空闲输入过程中自行重绘。**编辑已选中的主题后，也要再执行一次 `upwsh theme use "名称"`**。解析结果有缓存，不在每次按键时读取整个主题。

选中无效主题会报错并保留原选择。选择文件损坏或引用不受支持的主题时，已有会话保留上次可用主题，新会话回退到有效的 v2 pure-default。

## 从 v1 升级

**只支持 `Version: 2`，不兼容或自动转换 v1。** `Colors`、`Symbols`、`Display` 已删除；不能只把版本号从 1 改成 2。

更新会刷新 `themes/` 下的所有内置主题，补齐缺失文件；`custom/`、`custom/themes/`、工具和个人别名不会被覆盖。布局变更后的第一次更新会迁移旧的非内置主题。新会话会读取选择。自定义 v1 文件请参考 v2 模板手动重写。

卸载会删除 `themes/`；`--keep-custom` 会保留 `custom/`（包括 `custom/themes/`）和选择文件。卸载前另行备份。

## 最小分段示例

将下面内容保存为 `~/.config/upwsh/custom/themes/My Theme.json`，执行 `upwsh theme use "My Theme"`：

```json
{
  "Version": 2,
  "Name": "My Theme",
  "Order": ["user", "at", "host", "directory", "symbol", "space"],
  "Modules": {
    "user": { "Foreground": "#FFFFFF", "Background": "#2563EB" },
    "at": {
      "Type": "text", "Text": "@", "Foreground": "#93C5FD",
      "Background": "#2563EB", "AttachTo": ["user", "host"]
    },
    "host": { "Foreground": "#FDE68A", "Background": "#334155", "Suffix": " " },
    "directory": { "Foreground": "#EAB308", "Background": "transparent", "Suffix": " " },
    "symbol": {
      "Text": "❯", "Foreground": "#22C55E",
      "Failure": { "Text": "!", "Foreground": "#FCA5A5", "Background": "#7F1D1D" }
    },
    "space": { "Type": "text", "Text": " " }
  }
}
```

没有隐式空格。Colorful 在色块后用 `statusSpace` 留一个空格，耗时、错误码和提示字符直接相连，例如 ` 6s418ms1❯`、` 1❯`、` ❯`。用 `Prefix`、`Suffix` 或独立 `text` 段安排间距。模块隐藏时，它自己的前后文字也隐藏。最后的 `space` 使用默认背景，输入开始前渲染器会复位全部 ANSI 样式。

## 配置项

根对象：

| 字段 | 规则 |
| --- | --- |
| `Version` | 整数 `2` |
| `Name` | 与文件名一致，不含 `.json` |
| `Order` | 从左到右的模块名称数组，1–128 项，可重复；未列入的段不渲染 |
| `AddNewline` | 可选布尔值，省略为 `false`；提示符前增加一个空行。pure 默认关闭，colorful 默认开启。终端只能按整行留白，更细的行距需在终端配置中调整 |
| `Modules` | 1–64 个分段设置；内置名称区分大小写，自定义名称以英文字母开头，随后可用英文字母、数字、`_`、`-`，最多 40 字符 |
| `_Comment` | 可选说明，不参与渲染 |

每段通用选项：

| 字段 | 默认值与含义 |
| --- | --- |
| `Foreground` | `default`：终端默认文字色；也可填 `#RRGGBB` |
| `Background` | `transparent`：终端默认背景；也可填 `#RRGGBB` |
| `Enabled` | `true`；设为 `false` 不显示，也不查询该模块的数据 |
| `When` | `always`、`success` 或 `failure`；除 `exitCode` 默认 `failure` 外，都默认 `always` |
| `Bold` / `Italic` | 默认 `false`，是否加粗/斜体 |
| `Prefix` / `Suffix` | 默认空字符串，使用该段颜色；适合左右留白、括号或标签 |

**`transparent` 不是 alpha 透明度，也不是继承上一段背景**，而是显式恢复终端默认背景。终端窗口是否半透明由 WezTerm 等终端控制。颜色只接受六位十六进制，不接受 `#RRGGBBAA`。

内置段及其专有字段：

| 名称 | 内容与显示条件 |
| --- | --- |
| `user` | 用户名 |
| `host` | 小写主机名 |
| `directory` | 当前目录；`Style: "folder"` 为末级目录，`"path"` 为 Unix 风格路径；家目录显示 `~` |
| `git` | Git 分支；只在文件系统仓库中有值，无仓库或查询失败时隐藏 |
| `duration` | 上条命令耗时；大于 0 且达到 `MinMs` 才显示。`MinMs` 默认 `2000`，整数范围 `0`–`86400000` |
| `exitCode` | 默认只显示失败码；有效失败码缺失或为 0 时显示 `1`。显式设 `When: "always"` 可在成功时显示 `0` |
| `symbol` | `Text` 默认 `❯`；`Failure` 对象可在失败时覆盖 `Text`、`Foreground`、`Background`、`Bold`、`Italic` |

`When` 与数据条件同时满足才显示。例如 `duration.When: "failure"` 表示“失败且耗时达到门槛”。`symbol.Failure` 只覆盖写出的字段，其他值继承成功样式。

## 自定义文字与连接符

自定义名称必须有 `Type: "text"` 和 `Text`。可以放 `@`、空格、三角、缺口等符号，不执行脚本、不插值变量。

`AttachTo` 是可选数组：**数组中的所有内置模块都可见，文字段才显示**。目标必须在 `Order` 中；不支持绑定另一个文字段，避免循环依赖。默认 `[]` 表示独立显示。

例如给耗时加外部括号：

```json
"timeOpen":  { "Type": "text", "Text": "[", "AttachTo": ["duration"] },
"duration":  { "Foreground": "#73DACA", "MinMs": 2000 },
"timeClose": { "Type": "text", "Text": "] ", "AttachTo": ["duration"] }
```

把 `timeOpen`、`duration`、`timeClose` 连续放进 `Order`。耗时隐藏时两边括号一起消失。若括号不需要不同颜色，更简单的写法是直接给 `duration` 设置 `Prefix: "["` 和 `Suffix: "] "`。

### 箭头自动连接可见段

仅 `text` 的前景/背景支持：

- `previous.background`：前面最近的**可见内置段**背景。
- `next.background`：后面最近的**可见内置段**背景。

查找时跳过隐藏段及其他 `text` 段，重复引用的连接符按每个位置分别解析。没有邻居时回退到终端默认；当引用颜色用作前景、但邻居背景为 `transparent` 时，回退到 `default`，因为程序不知道终端默认背景的 RGB。

下面是可复制进主题的局部配置（还需保留根对象 `Version`、`Name`）：

```json
"Order": ["directory", "dirArrow", "git", "gitArrow", "duration", "timeArrow", "exitCode", "errorArrow", "symbol"],
"Modules": {
  "directory": { "Foreground": "#FFFFFF", "Background": "#1E40AF", "Prefix": " ", "Suffix": " " },
  "git": { "Foreground": "#FFFFFF", "Background": "#155E75", "Prefix": " ", "Suffix": " " },
  "duration": { "Foreground": "#FFFFFF", "Background": "#6B21A8", "Prefix": " ", "Suffix": " " },
  "exitCode": { "Foreground": "#FFFFFF", "Background": "#991B1B", "Prefix": " ", "Suffix": " " },
  "symbol": { "Text": " ❯ ", "Foreground": "#22C55E", "Background": "transparent" },
  "dirArrow": { "Type": "text", "Text": "", "AttachTo": ["directory"], "Foreground": "previous.background", "Background": "next.background" },
  "gitArrow": { "Type": "text", "Text": "", "AttachTo": ["git"], "Foreground": "previous.background", "Background": "next.background" },
  "timeArrow": { "Type": "text", "Text": "", "AttachTo": ["duration"], "Foreground": "previous.background", "Background": "next.background" },
  "errorArrow": { "Type": "text", "Text": "", "AttachTo": ["exitCode"], "Foreground": "previous.background", "Background": "next.background" }
}
```

箭头绑定它左边的模块。成功、短耗时、非仓库时，隐藏段连同自己的箭头消失，留下的箭头连接到下一可见段。不要用一个独立、无绑定的箭头夹在每两个条件段之间，那样数据消失后装饰仍会存在。

三角与缺口可拆为连续的两个文字段，分别设置 `Text` 为 ``、``，颜色与 `AttachTo` 相同。它们不会互相影响邻居取色。字符按终端单元格相邻绘制，不能重叠；Powerline 字形的贴合效果取决于终端和字体。

## 校验与开发

模板的 `_Comment` 有中文说明。实际配置写在 `Modules`，修改说明文字不会改变外观。标准 JSON 不使用尾逗号或 `//` 注释；布尔值不加引号。未知字段会报错，避免拼写错误被忽略。

主题名支持字母、数字、空格、`_`、`-`，以字母或数字开头，最多 80 字符，末尾不能有空格。文件不超过 64 KiB。配置文字单项最多 128 个 UTF-16 代码单元，允许空格，但不允许换行或控制字符。

CLI 管理安装目录；仓库的 `src/themes/` 只供源码开发和部署。`src/theme.psm1` 校验并补默认值，`src/prompt.psm1` 先判断可见数据、再渲染文字与连接符。隐藏 Git 段不查询 Git；同一渲染中重复引用 Git 只查询一次。空闲提示符缓存策略不变。
