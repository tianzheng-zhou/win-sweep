[English](README.md) | 中文

# win-sweep

**Windows 又卡了？开机转了半分钟？风扇莫名其妙狂转？**

你不是个例。每台 Windows 都逃不过同一个宿命——刚装完系统那会儿飞快，用个一两年，屎山就悄悄堆起来了。装软件送你一个自启服务，卸软件留你一堆注册表残留，厂商遥测在后台闷声跑了几百天你都不知道。等你终于受不了，想动手清理——打开注册表，又默默关上了。

win-sweep 不是又一个"一键优化大师"。它把系统清理的专业判断逻辑交给 AI，你只需要说人话：

```
你：电脑开机越来越慢了，帮我看看
AI：[运行诊断] 发现 47 个 Auto 服务、12 个启动项、3 个遥测计划任务...
    建议将以下 8 个服务改为 Manual：
    | # | 服务名         | 用途           | 风险 |
    | 1 | AdobeARMservice | Adobe 更新检查 | 低   |
    | ...
    确认执行？可以说"跳过 #3"来排除特定项。
```

**不背命令。不装软件。不交出控制权。** 每一步修改都等你点头，改了随时能回滚。

适用于任何能跑终端的 AI 编程工具：VS Code Copilot、Claude Code、Cursor、Windsurf、Codex CLI、Gemini CLI 等。

## 能做什么

| 功能 | 说明 | 脚本 |
|------|------|------|
| **系统体检** | 磁盘用量、内存占用 Top 30、启动项、服务、计划任务一览 | `diagnose.ps1` |
| **服务瘦身** | 自动识别可安全调整的服务，批量改为 Manual/Disabled | `optimize-services.ps1` |
| **启动项管理** | 禁用自启项并备份到 `RunDisabled`（随时可恢复） | `manage-startups.ps1` |
| **遥测围剿** | 服务 + 计划任务 + 启动项三层联查，防止遥测互相拉起 | `clean-tasks.ps1` |
| **可疑服务扫描** | 12 项风险信号量化评分，揪出残留/未签名/来路不明的服务 | `detect-suspicious.ps1` |
| **变更验证** | 自动校验每项修改是否生效，对比修改前后差异 | `verify.ps1` |

### 亮点

- **对话驱动** — 不用记命令，用自然语言说需求，AI 来执行
- **框架而非名单** — 内置的是通用判断逻辑，遇到未知服务也能分析，不依赖硬编码列表
- **遥测三层封杀** — 只禁服务没用（计划任务会拉起来），必须服务 + 任务 + 启动项一起禁
- **改了就能回滚** — 启动项备份不删除，服务优先 Manual 不 Disabled，高危操作先导出注册表
- **零依赖** — 纯 PowerShell 5.1，Windows 10/11 自带，不装任何第三方

## 快速开始

### 1. 安装

win-sweep 遵循 [Agent Skills](https://agentskills.io/) 开放标准——一个 `SKILL.md` 入口文件 + 支撑脚本和文档的目录结构。主流 AI 编程工具均已支持。

#### 方式 A：个人全局安装（推荐，所有项目可用）

直接克隆到对应工具的个人技能目录下。**只需选你用的工具。**

```powershell
# ✅ 跨工具通用路径（VS Code Copilot / Windsurf / Gemini CLI / Codex CLI 均识别）
git clone https://github.com/tianzheng-zhou/win-sweep.git "$HOME\.agents\skills\win-sweep"

# Claude Code（使用自己的路径，VS Code Copilot 也识别此路径）
git clone https://github.com/tianzheng-zhou/win-sweep.git "$HOME\.claude\skills\win-sweep"
```

> 如果你同时使用 Claude Code 和其他工具，需要**两个路径各克隆一份**。
>
> 更新：进入对应目录执行 `git pull` 即可。

<details>
<summary>各工具也有自己的专属路径（可选）</summary>

| 工具 | 个人技能目录 | 说明 |
|------|-------------|------|
| **VS Code Copilot** | `~/.copilot/skills/` | [文档](https://code.visualstudio.com/docs/copilot/customization/agent-skills)；也识别 `~/.claude/skills/` 和 `~/.agents/skills/` |
| **Claude Code** | `~/.claude/skills/` | [文档](https://code.claude.com/docs/en/skills) |
| **Windsurf** | `~/.codeium/windsurf/skills/` | [文档](https://docs.windsurf.com/windsurf/cascade/skills)；也识别 `~/.agents/skills/` |
| **Gemini CLI** | `~/.gemini/skills/` | [文档](https://geminicli.com/docs/cli/skills/)；也识别 `~/.agents/skills/`；支持 `gemini skills link <路径>` 一键安装 |
| **Codex CLI** | `~/.agents/skills/`（唯一路径） | [文档](https://developers.openai.com/codex/skills) |

</details>

#### 方式 B：项目级安装（仅当前项目可用）

克隆到项目的技能目录下，可随项目提交到版本控制：

```powershell
# 以 .agents/skills/ 为例（覆盖最多工具）
git clone https://github.com/tianzheng-zhou/win-sweep.git .agents/skills/win-sweep
```

各路径兼容情况：

| 路径 | 识别的工具 |
|------|-----------|
| `.agents/skills/win-sweep/` | VS Code Copilot, Windsurf, Gemini CLI, Codex CLI |
| `.claude/skills/win-sweep/` | Claude Code, VS Code Copilot |
| `.github/skills/win-sweep/` | VS Code Copilot |
| `.windsurf/skills/win-sweep/` | Windsurf |
| `.gemini/skills/win-sweep/` | Gemini CLI |

> 推荐 `.agents/skills/`——一份文件覆盖最多工具。如果团队也用 Claude Code，再加一份到 `.claude/skills/`。

#### Cursor 用户

Cursor 暂不支持 Agent Skills 标准，需通过 [Rules](https://docs.cursor.com/context/rules) 引入：

1. 将 win-sweep 克隆到项目目录下
2. 创建 `.cursor/rules/win-sweep.md`，内容引用 SKILL.md 和脚本路径

#### 其他工具

将 win-sweep 目录放在项目中，手动引导 AI 阅读 `SKILL.md` 即可。

### 2. 开始对话

直接向 AI 描述你的问题：

```
> 帮我做个系统体检
> 有没有可以关掉的开机自启服务？
> 扫一下遥测组件，全部关掉
> 检查有没有可疑的服务残留
> 我的 C 盘快满了，看看哪里占空间
```

AI 会调用对应脚本，分析结果后给出建议并等你确认。

### 3. 管理员权限（可选）

诊断扫描不需要管理员。但修改服务、计划任务等操作需要提权。

**方法：以管理员身份启动你的 AI 工具，内部命令自动继承权限。**

| 工具 | 提权方式 |
|------|----------|
| VS Code / Cursor / Windsurf | 右键应用图标 → 以管理员身份运行 |
| 终端类（Claude Code / Codex CLI / Gemini CLI 等）| 先开管理员终端，再启动工具 |

> 不提权也能用——遇到权限不足时 AI 会提前告知，不会直接报错。

<details>
<summary>各操作权限要求</summary>

| 操作 | 需要管理员 |
|------|------------|
| 系统诊断 | 部分（服务详情需要） |
| 服务优化 | 是 |
| HKCU 启动项 | 否 |
| HKLM 启动项 | 是 |
| 计划任务清理 | 是 |
| 可疑服务检测 | 是 |
| 变更验证 | 部分 |

</details>

## 安全设计

**你始终拥有最终决定权。** 每一项修改都在你确认后才执行。

| 风险等级 | 示例 | 怎么确认 |
|----------|------|----------|
| 只读 | 诊断扫描 | 直接运行，不问 |
| 低危 | 服务 Auto → Manual | 汇总表一次确认，可排除个别项 |
| 中危 | 服务 → Disabled、禁用计划任务 | 汇总确认 + 影响说明 |
| 高危 | 删除服务/注册表项 | **先备份** → 逐项确认 → 给出回滚命令 |

其他防护措施：

- 首次修改前建议创建**系统还原点**
- 每次修改记录**时间戳 + 原值 → 新值 + 执行命令**，便于审计
- 启动项"禁用"实际是移到 `RunDisabled` 键备份，一条命令恢复

## 项目结构

```
win-sweep/
├── SKILL.md                    # 技能入口（AI 读取此文件获取指令）
├── scripts/                    # PowerShell 工具脚本
│   ├── diagnose.ps1            # 系统诊断（只读）
│   ├── optimize-services.ps1   # 服务启动模式批量调整
│   ├── manage-startups.ps1     # 启动项禁用/恢复
│   ├── clean-tasks.ps1         # 计划任务扫描与禁用
│   ├── detect-suspicious.ps1   # 可疑服务风险评分
│   └── verify.ps1              # 变更验证与前后对比
└── references/                 # AI 参考文档（按需加载）
    ├── service-rules.md        # 服务判断框架
    ├── telemetry.md            # 遥测识别与三层禁用
    ├── suspicious-checklist.md # 12 项风险评分体系
    └── sc-gotchas.md           # sc.exe / PowerShell 常见陷阱
```

## 环境要求

- Windows 10 / 11
- PowerShell 5.1+（系统自带）
- 无需安装任何第三方依赖

## 免责声明

> 本工具通过 AI 辅助修改 Windows 系统配置。虽然内置了分级安全机制，但**系统配置修改具有固有风险**。你需要自行判断是否接受每一项修改。作者不对因使用本工具导致的任何损失承担责任。建议操作前创建系统还原点。

## 许可证

[MIT](LICENSE)
