# WinSweep

一个 VS Code Copilot Skill，用于 Windows 系统清理与优化。

## 功能

WinSweep 通过 PowerShell 脚本诊断和清理 Windows 系统膨胀：

- **系统诊断** — 扫描磁盘用量、已安装软件、启动项、服务、计划任务
- **服务优化** — 批量将不必要的 Auto 服务改为 Manual/Disabled
- **启动项管理** — 禁用启动项并安全备份到 `RunDisabled` 注册表键
- **计划任务清理** — 禁用不必要的计划任务（特别是绕过服务禁用的遥测任务）
- **可疑服务检测** — 查找残留、未签名或来源不明的服务

## 安装

复制此文件夹到 Copilot 技能目录：

```
~/.copilot/skills/winsweep/
```

或克隆到项目中：

```
.github/skills/winsweep/
```

## 使用

当你向 Copilot 询问 Windows 系统清理、服务优化、启动项管理或磁盘空间回收时，此技能会自动触发。

也可以直接调用：

```
/winsweep
```

## 环境要求

- Windows 10/11
- PowerShell 5.1+（需管理员权限）
- 无外部依赖

## 项目结构

```
WinSweep/
├── SKILL.md              # 技能定义（Copilot 读取此文件）
├── README.md             # 本文件
├── LICENSE               # MIT
├── scripts/              # PowerShell 脚本
│   ├── diagnose.ps1      # 系统诊断
│   ├── optimize-services.ps1  # 服务优化
│   ├── manage-startups.ps1    # 启动项管理
│   ├── clean-tasks.ps1        # 计划任务清理
│   ├── detect-suspicious.ps1  # 可疑服务检测
│   └── verify.ps1             # 变更验证
├── references/           # 参考文档（按需加载）
│   ├── service-rules.md       # 服务优化规则
│   ├── telemetry.md           # 已知遥测服务
│   ├── suspicious-checklist.md # 可疑服务排查
│   └── sc-gotchas.md          # sc.exe 常见坑
└── docs/                 # 本地笔记（不上传）
    └── .local/
```

## 许可证

MIT
