# 服务优化规则

哪些服务可以安全地从 Auto 改为 Manual 或 Disabled。

## 可安全改为 Manual（Auto → Manual）

这些服务改为 Manual 后，打开对应软件时 Windows 会自动拉起。

### 工程软件
| 服务 | 软件 | 说明 |
|------|------|------|
| SolidWorks Flexnet Server | SOLIDWORKS | 许可证服务器，打开 SW 时自动启动 |
| FlexNet Licensing Service | 多种 | 共享许可证管理器 |
| hasplms (Sentinel) | HASP 加密狗 | 硬件许可证保护 |
| FirebirdGuardianDefaultInstance | SOLIDWORKS Electrical | 内嵌数据库 |
| AdskLicensingService | Autodesk | 许可证服务 |

### SQL Server
| 服务 | 说明 |
|------|------|
| MSSQLSERVER | 默认实例 |
| MSSQL$*实例名* | 命名实例 — 注意 PowerShell 中 `$` 的转义 |
| SQLBrowser | 实例发现 |
| SQLWriter | VSS 集成 |

### 打印机 / 外设
| 服务 | 说明 |
|------|------|
| Spooler | 打印后台处理程序 — 不常打印可改 Manual |
| HP* | HP 打印机相关服务 |
| Apple Mobile Device Service | iTunes/iPhone 同步 |
| Bonjour Service | Apple 网络发现 |

### 虚拟化
| 服务 | 说明 |
|------|------|
| vmms | Hyper-V 虚拟机管理 |
| WSLService | Windows 子系统 for Linux |
| CmService | 容器管理器 |

### 其他
| 服务 | 说明 |
|------|------|
| Everything | 文件搜索索引 |
| ZeroTierOneService | VPN — 需要时手动启动 |

## 可安全禁用（Disabled）

这些服务没有实际价值，可能存在安全/隐私风险。

| 服务 | 理由 |
|------|------|
| Flash Helper Service | Flash 已于 2020 年终止，安全风险 |
| FlashCenterSvc | Flash 已终止，广告推送渠道 |
| SQLTELEMETRY* | SQL Server 遥测 |
| DiagTrack | Windows 遥测 |
| ESRV_SVC_QUEENCREEK | Intel 遥测 |
| SystemUsageReportSvc_QUEENCREEK | Intel 遥测 |
| MapsBroker | 离线地图（大部分系统不需要） |
| wisvc | Windows 预览体验成员（LTSC 不需要） |

## 禁止修改

| 服务 | 理由 |
|------|------|
| wuauserv | Windows Update |
| WinDefend | Windows Defender |
| EventLog | 事件日志 |
| RpcSs | RPC — 系统关键 |
| DCOM Server Process Launcher | 系统关键 |
