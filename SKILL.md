---
name: winsweep
description: "Windows 系统清理与优化工具包。Use when: Windows cleanup, 系统清理, 禁用服务, 禁用启动项, 开机加速, 磁盘空间释放, 卸载残留清理, 遥测服务移除, 可疑服务检测, 计划任务清理, 服务审计, 启动项审计, disable services, disable startup items, reduce boot time, free disk space, telemetry removal, suspicious service detection, scheduled task cleanup"
---

# WinSweep — Windows 系统清理与优化

诊断和清理 Windows 系统膨胀问题的技能：冗余服务、启动项、计划任务、磁盘空间占用、可疑进程。

## 何时使用

- 系统变慢或开机时间过长
- 磁盘空间不足（C 盘或 D 盘）
- 启动项或后台服务过多
- 需要审计/禁用遥测服务（Intel、Microsoft、SQL Server）
- 发现可疑或残留服务
- 工程软件（SOLIDWORKS、AutoCAD、MATLAB）注册了大量自启动服务
- 软件卸载后需要清理残留

## 操作流程

### 第一阶段：诊断

运行诊断脚本，评估系统状态：

1. [系统概览](./scripts/diagnose.ps1) — 磁盘用量、已安装软件、启动项、服务、计划任务、内存占用排行
2. 查看输出，确定优化目标

### 第二阶段：优化

根据诊断结果，执行针对性修复：

1. [服务优化](./scripts/optimize-services.ps1) — 批量修改服务启动模式（Auto → Manual/Disabled）
2. [启动项管理](./scripts/manage-startups.ps1) — 禁用启动项并备份到 `RunDisabled` 注册表键
3. [计划任务清理](./scripts/clean-tasks.ps1) — 禁用不必要的计划任务
4. [可疑服务检测](./scripts/detect-suspicious.ps1) — 查找残留/未签名/可疑服务

### 第三阶段：验证

1. [验证脚本](./scripts/verify.ps1) — 确认变更已正确生效
2. 重启后重新运行诊断，对比前后差异

## 核心原则

- **优先 Manual 而非 Disabled** — 用 `start= demand` 而非 `start= disabled`，Windows 会在需要时自动拉起 Manual 服务
- **先备份再修改** — 启动项移到 `RunDisabled` 而非直接删除；修改服务前先导出配置
- **遥测三层排查** — 必须同时检查 服务 + 计划任务 + 启动项（Intel esrv.exe 是经典案例）
- **需要管理员权限** — 大部分操作需要提升权限的 PowerShell

## 参考文档

- [服务优化规则](./references/service-rules.md) — 哪些服务可以安全修改
- [已知遥测服务](./references/telemetry.md) — Intel、Microsoft、SQL Server 遥测识别
- [可疑服务排查清单](./references/suspicious-checklist.md) — 如何识别和处理未知服务
- [sc.exe 常见坑](./references/sc-gotchas.md) — sc.exe 和 PowerShell 的常见陷阱
