# 已知遥测服务

如何跨三个层面完全禁用遥测。

## 三层排查规则

遥测厂商通常会注册多个持久化机制。只禁用服务是不够的。

| 层面 | 检查方式 | 命令 |
|------|----------|------|
| Service | `sc.exe query` | `sc.exe config <name> start= disabled` |
| Scheduled Task | `Get-ScheduledTask` | `Disable-ScheduledTask -TaskName <name>` |
| Startup Item | `reg query HKCU\...\Run` | Move to `RunDisabled` |

**必须同时检查所有三个层面。**

## Intel 遥测

| 组件 | 类型 | 名称 |
|-----------|------|------|
| Service | Service | `ESRV_SVC_QUEENCREEK` |
| Service | Service | `SystemUsageReportSvc_QUEENCREEK` |
| Task | Scheduled Task | `USER_ESRV_SVC_QUEENCREEK` |
| Task | Scheduled Task | `IntelSURQC-Upgrade-*` |
| Task | Scheduled Task | `IntelSURQC-Upgrade-*-Logon` |

**已知行为**：仅禁用服务不能阻止 `esrv.exe`。计划任务 `USER_ESRV_SVC_QUEENCREEK` 会在用户登录时拉起进程，占用约 138 MB 内存。

## Microsoft 遥测

| 组件 | 类型 | 名称 |
|-----------|------|------|
| Service | Service | `DiagTrack` (Connected User Experiences and Telemetry) |
| Task | Scheduled Task | Various under `\Microsoft\Windows\Application Experience\` |

## SQL Server 遥测

| 组件 | 类型 | 名称 |
|-----------|------|------|
| Service | Service | `SQLTELEMETRY` |
| Service | Service | `SQLTELEMETRY$<instance>` |

## Flash（已终止 — 安全风险）

| 组件 | 类型 | 名称 |
|-----------|------|------|
| Service | Service | `Flash Helper Service` |
| Service | Service | `FlashCenterSvc` |

Flash 已于 2020 年 12 月终止支持。这些服务是广告推送和漏洞利用的渠道，应禁用并卸载。
