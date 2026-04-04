# 服务优化规则

本文档为 AI 提供**判断框架**，用于评估任意 Windows 服务是否可以安全修改。
不依赖硬编码白名单——AI 应基于下述规则对诊断扫描出的每个服务做出独立判断。

---

## 核心原则

1. **优先 Manual，慎用 Disabled** — `start= demand` 让 Windows 在需要时自动拉起服务；`start= disabled` 则完全阻止启动，可能导致依赖它的软件报错。只有确认无任何软件依赖时才用 Disabled。
2. **判断依据是"该服务是否需要常驻"** — 大量服务设为 Auto 只是厂商图省事，实际按需启动即可。
3. **遥测类服务可直接 Disabled** — 纯数据采集，不影响功能。但需同时排查计划任务和启动项（见 [telemetry.md](./telemetry.md)）。
4. **已终止/已卸载软件的残留服务可删除** — 可执行文件不存在的服务没有保留价值。

---

## 判断框架：对任意服务的决策流程

遇到一个 Auto 启动的服务时，按以下顺序判断：

```
1. 是否属于"禁止修改"类别？
   → 是：跳过，不动
   → 否：继续

2. 可执行文件是否存在？
   → 不存在：建议删除（sc.exe delete）
   → 存在：继续

3. 是否为遥测/数据采集类？
   → 是：建议 Disabled + 排查计划任务
   → 否：继续

4. 是否为已终止产品（如 Flash）？
   → 是：建议 Disabled 或删除
   → 否：继续

5. 是否为按需使用的软件（非常驻需求）？
   → 是：建议 Manual
   → 否：保持 Auto
```

---

## 禁止修改（硬性规则）

以下**类别**的服务绝对不能动。识别方式是判断服务的功能角色，而非穷举服务名。

### 绝对禁止
| 类别 | 代表服务 | 说明 |
|------|----------|------|
| RPC / COM 基础设施 | `RpcSs`, `RpcEptMapper`, `DcomLaunch` | 几乎所有进程间通信的基础，停掉系统立刻异常 |
| Windows Update | `wuauserv`, `UsoSvc` | 安全更新通道 |
| 安全防护 | `WinDefend`, `WdNisSvc`, `SecurityHealthService` | Defender 防病毒 |
| 事件日志 | `EventLog` | 审计和故障排查的基础 |
| 网络核心 | `Dhcp`, `Dnscache`, `NlaSvc`, `nsi` | 停掉直接断网 |
| 用户登录 | `LSM`, `Winlogon`（非服务但相关）, `SamSs`, `Netlogon`（域） | 无法登录 |
| 存储 | `StorSvc`, `VDS` | 磁盘管理 |
| 加密 | `CryptSvc`, `KeyIso` | 证书、HTTPS、驱动签名验证 |
| 电源管理 | `Power` | 笔记本合盖/休眠依赖 |
| 组件服务 | `TrustedInstaller`, `msiserver` | 软件安装和 Windows 更新依赖 |

### 判断原则
- 服务描述中含 "critical"、"必须运行" 等字样 → 高度警惕
- `svchost.exe -k netsvcs` 组中的核心服务 → 逐个确认再动
- 不确定时保持 Auto — 宁可多跑一个服务，不冒系统挂掉的风险

---

## 可安全改为 Manual 的模式（Auto → Manual）

以下是**通用模式**，适用于任何系统。AI 应根据诊断结果匹配这些模式。

### 模式 1：软件许可证/激活服务
**特征**：服务名或描述含 `license`、`flexnet`、`sentinel`、`hasp`、`activation`
**理由**：只在打开对应软件时需要，软件会自动拉起 Manual 服务
**示例**：FlexNet Licensing Service, hasplms, AdskLicensingService, SolidWorks Flexnet Server

### 模式 2：数据库引擎
**特征**：服务名含 `SQL`、`MySQL`、`PostgreSQL`、`Mongo`、`Firebird`、`Oracle`
**理由**：开发/工程环境的数据库不需要常驻，打开客户端工具时启动即可
**示例**：MSSQLSERVER, MSSQL$实例名, SQLBrowser, SQLWriter, FirebirdGuardianDefaultInstance, MySQL80
**注意**：PowerShell 中 `$` 需要转义（`` `$ `` 或用单引号包裹服务名）

### 模式 3：打印服务
**特征**：服务名含 `Print`、`Spooler`，或厂商前缀（`HP`、`Canon`、`Epson`、`Brother`）
**理由**：不打印时无需运行；`Spooler` 有历史漏洞（PrintNightmare），不常用可关
**示例**：Spooler, HPAppHelperCap, Canon IJ Network

### 模式 4：外设同步/管理
**特征**：服务属于非常驻外设（手机同步、蓝牙附件管理、手写板等）
**示例**：Apple Mobile Device Service, Bonjour Service, WTabletServicePro（Wacom）

### 模式 5：虚拟化平台
**特征**：服务名含 `vmms`、`Hyper-V`、`WSL`、`Docker`、`Container`、`VBox`
**理由**：不使用虚拟机/容器时无需常驻
**示例**：vmms, WSLService, CmService, com.docker.service, VBoxSDS

### 模式 6：软件自动更新服务
**特征**：服务名或描述含 `update`、`updater`，且非 Windows Update
**理由**：第三方更新服务常驻只为定期检查更新，完全可以按需
**示例**：gupdate/gupdatevm（Google）, MicrosoftEdgeUpdate, AdobeARMservice, MozillaMaintenance, brave, opera
**注意**：不要动 `wuauserv`（Windows Update）和 `UsoSvc`

### 模式 7：厂商后台服务（非核心功能）
**特征**：显卡驱动附属服务、OEM 预装服务、品牌硬件管理
**示例**：NVDisplay.ContainerLocalSystem（NVIDIA Container）, AMD Crash Defender, Intel(R) TPM Provisioning Service, LenovoVantageService, HPSupportAssistance
**判断**：不影响硬件核心功能（出图/运算），只是附加的监控/优化/推广

### 模式 8：搜索/索引服务
**特征**：服务名含 `Search`、`Index`，或第三方搜索工具
**示例**：WSearch（Windows Search）, Everything, Listary
**判断**：SSD 系统上 WSearch 的 Manual 影响不大；HDD 系统如依赖搜索功能则保持 Auto

---

## 可安全禁用的模式（Disabled）

### 模式 A：遥测/数据采集
**特征**：服务名或描述含 `telemetry`、`diagnostic`、`CEIP`、`usage report`、`SQM`
**示例**：DiagTrack, SQLTELEMETRY*, ESRV_SVC_QUEENCREEK, SystemUsageReportSvc_QUEENCREEK
**重要**：必须同时排查计划任务（见 telemetry.md），否则计划任务会重新拉起进程

### 模式 B：已终止/过时产品
**特征**：属于已 EOL 的产品，或厂商已停止维护
**示例**：Flash Helper Service, FlashCenterSvc
**理由**：无安全更新 = 漏洞利用入口

### 模式 C：当前系统不适用的功能
**特征**：服务提供的功能在当前环境下确定不需要
**示例**：
| 服务 | 条件 |
|------|------|
| `MapsBroker` | 不使用离线地图 |
| `wisvc` | 非 Insider Preview 用户 |
| `Fax` | 不用传真 |
| `RemoteRegistry` | 不需要远程注册表访问（也有安全风险） |
| `RetailDemo` | 非零售展示机 |
| `WpcMonSvc` | 无家长控制需求 |

---

## 边界情况和注意事项

- **SysMain（Superfetch）**：SSD 系统上收益很小，可改 Manual；HDD 系统保持 Auto
- **WSearch**：同上逻辑，取决于存储介质和使用习惯
- **TabletInputService**：不用触摸屏/手写笔可改 Manual，但有些触摸板手势依赖它
- **多个厂商服务联动**：HP、Lenovo、Dell 等 OEM 常注册 3-5 个互相依赖的服务，改之前查依赖关系（`sc.exe enumdepend`）
- **域环境额外注意**：`Netlogon`、`LanmanWorkstation`、`LanmanServer` 在域环境中不可动
