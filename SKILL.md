---
name: win-sweep
description: "Windows 系统清理与优化工具包。Use when: Windows cleanup, 系统清理, 禁用服务, 禁用启动项, 开机加速, 磁盘空间释放, 卸载残留清理, 遥测服务移除, 可疑服务检测, 计划任务清理, 服务审计, 启动项审计, disable services, disable startup items, reduce boot time, free disk space, telemetry removal, suspicious service detection, scheduled task cleanup"
license: MIT
---

# win-sweep — Windows 系统清理与优化

诊断和清理 Windows 系统膨胀问题的技能：冗余服务、启动项、计划任务、磁盘空间占用、可疑进程。

## 何时使用

- 系统变慢或开机时间过长
- 磁盘空间不足（C 盘或 D 盘）
- 启动项或后台服务过多
- 需要审计/禁用遥测组件
- 发现可疑或残留服务
- 第三方软件注册了大量自启动服务
- 软件卸载后需要清理残留

## 操作流程

### 第一阶段：诊断（安全 — 无需确认）

运行诊断脚本，评估系统状态。诊断操作纯只读，不修改系统，可随时运行。

1. [系统概览](./scripts/diagnose.ps1) — 磁盘用量、已安装软件、启动项、服务、计划任务、内存占用排行
2. 查看输出，确定优化目标

### 第二阶段：优化（危险 — 必须确认）

根据诊断结果，执行针对性修复。**所有修改操作必须遵守下方安全机制。**

1. [服务优化](./scripts/optimize-services.ps1) — 批量修改服务启动模式（Auto → Manual/Disabled）
2. [启动项管理](./scripts/manage-startups.ps1) — 禁用启动项并备份到 `RunDisabled` 注册表键
3. [计划任务清理](./scripts/clean-tasks.ps1) — 禁用不必要的计划任务
4. [可疑服务检测](./scripts/detect-suspicious.ps1) — 查找残留/未签名/可疑服务

### 第三阶段：验证（安全 — 无需确认）

1. [验证脚本](./scripts/verify.ps1) — 确认变更已正确生效
2. 重启后重新运行诊断，对比前后差异

---

## 安全机制（铁律）

### 一、操作分级

不同操作的风险等级不同，确认要求也不同。

| 等级 | 操作类型 | 示例 | 可逆性 | 确认要求 |
|------|----------|------|--------|----------|
| **只读** | 诊断、扫描、查询 | `Get-CimInstance`、`Get-ScheduledTask` | — | 不需确认 |
| **低危** | Auto → Manual | 服务设为按需启动 | 可逆：改回 Auto | 汇总表确认 |
| **中危** | Auto → Disabled、禁用计划任务 | 完全阻止启动 | 可逆：改回 Auto/Enable | 汇总表确认 + 标注影响 |
| **高危** | 删除服务、删除注册表项 | `sc.exe delete`、删除启动项 | **需先备份**才可逆 | 逐项确认 + 备份证据 |

### 二、确认流程

#### 批量操作（低危/中危）：汇总表确认

多个同级操作时，呈现汇总表让用户一次确认，而非逐个询问：

```
我建议对以下 N 个服务进行调整：

| # | 服务名 | 当前状态 | 建议操作 | 用途 | 风险 |
|---|--------|----------|----------|------|------|
| 1 | ServiceA | Auto/Running | → Manual | XX 许可证服务 | 低 |
| 2 | ServiceB | Auto/Stopped | → Disabled | XX 遥测 | 低 |
| ...

说明：
- Manual 服务在对应软件打开时会自动启动，日常使用无感
- 如需恢复，可随时改回 Auto

是否确认执行？你也可以说"跳过 #2"来排除特定项。
```

用户可以：
- 全部确认（"确认"、"执行"、"好的"）
- 部分排除（"跳过 #2 和 #5"）
- 全部拒绝（"不了"、"取消"）

#### 高危操作：逐项确认 + 备份

删除类操作必须：
1. **先执行备份**并告知用户备份位置
2. **逐项报告**：这是什么、为什么建议删除、删除后果、回滚方式
3. **等待用户对每一项单独确认**

```
⚠️ 高危操作：删除服务 "SuspiciousService"

- 这是什么：可执行文件 C:\ProgramData\xxx.exe 已不存在的残留服务
- 排查结果：风险评分 7/12（文件不存在 +3, 乱码服务名 +4）
- 已备份：注册表已导出到 %TEMP%\svc-backup-SuspiciousService.reg
- 回滚方式：reg import "%TEMP%\svc-backup-SuspiciousService.reg" + 重启
- 操作命令：sc.exe delete "SuspiciousService"

是否执行？
```

### 三、系统还原点

在**第一次执行修改操作之前**，建议用户创建系统还原点：

```
即将开始修改系统配置。建议先创建系统还原点，以便在出现问题时整体回滚。

创建命令：Checkpoint-Computer -Description "win-sweep pre-optimization" -RestorePointType MODIFY_SETTINGS

是否现在创建？（如果你已有近期还原点，可以跳过）
```

如果用户拒绝，记录但不阻止后续操作——这是建议而非强制。

### 四、变更日志

每次执行修改操作后，在终端输出中记录：
- 时间戳
- 操作内容（原始值 → 新值）
- 执行的命令

方便用户事后审计和定位问题。

---

## 核心原则

- **优先 Manual 而非 Disabled** — `start= demand` 让 Windows 在需要时自动拉起服务；`start= disabled` 完全阻止启动。除非是遥测/已终止产品，否则用 Manual
- **先备份再修改** — 启动项移到 `RunDisabled` 而非直接删除；服务删除前先 `reg export`
- **遥测三层排查** — 必须同时检查 服务 + 计划任务 + 启动项，只禁一层无效（见 [telemetry.md](./references/telemetry.md)）
- **判断框架优先于名单** — 参考文档提供的是通用识别模式，而非硬编码的服务名列表。遇到未知服务应套用框架判断，而非仅匹配已知列表
- **需要管理员权限** — 大部分操作需要提升权限的 PowerShell

## 参考文档

按需加载——遇到具体问题时再读取对应文档，无需全部预加载。

- [服务优化规则](./references/service-rules.md) — 判断框架：任意服务是否可安全修改的决策流程 + 通用模式匹配
- [遥测识别与禁用](./references/telemetry.md) — 遥测组件的识别框架（关键词模式 + 行为特征）+ 已知厂商案例 + 三层禁用模板
- [可疑服务排查清单](./references/suspicious-checklist.md) — 量化风险评分体系（12 个信号）+ 排查流程 + 决策矩阵 + 误报排除
- [PowerShell 和 sc.exe 陷阱](./references/sc-gotchas.md) — AI 生成 PowerShell 的高频错误（`&&`、比较运算符、数组展开等）+ sc.exe 专项坑 + 自检清单
