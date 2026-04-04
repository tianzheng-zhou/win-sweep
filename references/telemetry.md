# 遥测识别与禁用

本文档为 AI 提供**识别框架**，用于发现和完整禁用 Windows 系统中的遥测/数据采集组件。
核心挑战：遥测厂商会注册多个持久化机制互相拉起，只禁用其中一层是无效的。

---

## 三层排查规则（铁律）

遥测必须在**所有三个层面**同时禁用，否则会复活。

| 层面 | 扫描命令 | 禁用命令 | 漏掉的后果 |
|------|----------|----------|------------|
| 服务 | `Get-CimInstance Win32_Service \| Where-Object { $_.Name -match '<pattern>' }` | `sc.exe config "<name>" start= disabled` | 计划任务或启动项会把服务拉起 |
| 计划任务 | `Get-ScheduledTask \| Where-Object { $_.TaskName -match '<pattern>' }` | `Disable-ScheduledTask -TaskName "<name>"` | 任务在登录/定时触发时直接运行进程，绕过服务 |
| 启动项 | `Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` | 移到 `RunDisabled` 键（见 manage-startups.ps1） | 用户登录时拉起进程 |

### 排查流程

对每个疑似遥测厂商：

1. **服务层** — 按厂商关键词搜索服务名和可执行路径
2. **任务层** — 按厂商关键词和可执行文件名搜索计划任务
3. **启动项层** — 在 `Run` / `RunOnce` 键中搜索同名可执行文件
4. **交叉验证** — 禁用后重启，检查进程是否仍在运行（`Get-Process`）

---

## 如何识别未知的遥测组件

已知厂商只是冰山一角。AI 应能识别**任何**遥测组件，而非仅匹配下方列表。

### 遥测特征关键词

服务名、描述、可执行路径或计划任务名中出现以下模式，高度暗示遥测：

| 类别 | 关键词模式（正则） | 说明 |
|------|---------------------|------|
| 直接标识 | `telemetry\|CEIP\|SQM\|DiagTrack` | 明确的遥测/客户体验改善计划 |
| 数据上报 | `usage.?report\|crash.?report\|error.?report\|feedback` | 使用数据/崩溃报告上传 |
| 数据采集 | `collect\|harvest\|beacon\|analytics\|metrics\|heartbeat` | 通用采集术语 |
| 厂商遥测 | `QUEENCREEK\|esrv\|SUR\|PimIndexMaint\|OfficeTelemetry` | 已知厂商特有标识 |

### 行为特征

| 特征 | 说明 |
|------|------|
| 服务设为 Auto 但无用户可见功能 | 纯后台数据上传 |
| 计划任务触发器为"登录时"或"每日" | 定期采集 |
| 可执行文件名含 `report`、`send`、`upload` | 上报功能 |
| 网络连接目标为 `*.data.microsoft.com`、`telemetry.*`、`*.events.data.*` | 已知遥测端点 |
| 禁用服务后仍有同名进程运行 | 被计划任务或启动项拉起 — 典型的三层持久化 |

---

## 已知遥测厂商

以下为常见案例，供 AI 在扫描结果中快速匹配。表中 `S` = 服务，`T` = 计划任务，`R` = 启动项/注册表。

### Intel

| 类型 | 名称 | 说明 |
|------|------|------|
| S | `ESRV_SVC_QUEENCREEK` | Intel 软件使用报告 |
| S | `SystemUsageReportSvc_QUEENCREEK` | 系统使用数据采集 |
| T | `USER_ESRV_SVC_QUEENCREEK` | 登录时拉起 esrv.exe |
| T | `IntelSURQC-Upgrade-*` | 升级检查 |
| T | `IntelSURQC-Upgrade-*-Logon` | 登录时升级检查 |

**陷阱**：仅禁用服务无效。`USER_ESRV_SVC_QUEENCREEK` 任务在用户登录时直接运行 `esrv.exe`（约 138 MB 内存），完全绕过服务。这是三层排查规则存在的原因。

### Microsoft

| 类型 | 名称 | 说明 |
|------|------|------|
| S | `DiagTrack` | Connected User Experiences and Telemetry — 主遥测服务 |
| S | `dmwappushservice` | WAP Push 消息路由，DiagTrack 的数据通道 |
| T | `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser` | 兼容性评估（定期扫描已安装软件） |
| T | `\Microsoft\Windows\Application Experience\ProgramDataUpdater` | 程序数据更新 |
| T | `\Microsoft\Windows\Autochk\Proxy` | 采集并上传 SQM 数据 |
| T | `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator` | CEIP 数据合并上传 |
| T | `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip` | USB 设备的 CEIP |
| T | `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | 磁盘诊断数据采集 |

**注意**：
- `DiagTrack` 禁用后 Windows 可能在大版本更新时重新启用，需更新后复查
- 组策略 `Computer Configuration > Administrative Templates > Windows Components > Data Collection` 可从策略层面控制，比逐个禁用更持久

### SQL Server

| 类型 | 名称 | 说明 |
|------|------|------|
| S | `SQLTELEMETRY` | 默认实例遥测 |
| S | `SQLTELEMETRY$<instance>` | 命名实例遥测（PowerShell 中 `$` 需转义） |

### NVIDIA

| 类型 | 名称 | 说明 |
|------|------|------|
| S | `NvTelemetryContainer` | NVIDIA 遥测容器（较新驱动已移除，旧版仍存在） |
| T | `NvTmMon_*` | 遥测监控任务 |
| T | `NvTmRep_*` | 遥测报告任务 |

**注意**：NVIDIA 在较新的 GeForce Experience / NVIDIA App 中将遥测合并进了 `NVDisplay.ContainerLocalSystem`，不再单独注册 `NvTelemetryContainer`。如需彻底禁用，需在 NVIDIA App 设置中关闭。

### OEM 厂商（Lenovo / Dell / HP）

OEM 预装软件普遍包含遥测组件，命名不统一，按以下模式搜索：

| 厂商 | 服务/任务关键词模式 | 常见组件 |
|------|---------------------|----------|
| Lenovo | `Lenovo.*metric\|Lenovo.*telemetry\|ImController` | Lenovo Vantage 遥测、System Update 数据采集 |
| Dell | `Dell.*telemetry\|DellDataVault\|SupportAssist` | Dell SupportAssist 诊断数据上传 |
| HP | `HP.*telemetry\|HPDiag\|HpTouchpoint` | HP Touchpoint Analytics（已知隐私争议） |

**处理原则**：OEM 遥测组件通常可以安全禁用。主功能（驱动更新、保修查询）不依赖遥测。

### Adobe

| 类型 | 名称 | 说明 |
|------|------|------|
| S | `AdobeARMservice` | 更新检查（兼有遥测，见模式 6 in service-rules.md） |
| T | `Adobe Acrobat Update Task` | 定期更新检查 |
| T | `AdobeGCInvoker-*` | Adobe Genuine Copy 验证（含上报） |

---

## 禁用操作模板

### 单个厂商的完整禁用流程

```powershell
# === 以 Intel 遥测为例 ===

# 1. 禁用服务
sc.exe config "ESRV_SVC_QUEENCREEK" start= disabled
sc.exe config "SystemUsageReportSvc_QUEENCREEK" start= disabled

# 2. 停止正在运行的服务
sc.exe stop "ESRV_SVC_QUEENCREEK"
sc.exe stop "SystemUsageReportSvc_QUEENCREEK"

# 3. 禁用计划任务
Get-ScheduledTask | Where-Object { $_.TaskName -match 'ESRV|IntelSURQC' } |
    Disable-ScheduledTask

# 4. 检查启动项（Run 键）
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" |
    ForEach-Object { $_.PSObject.Properties } |
    Where-Object { $_.Value -match 'esrv|IntelSUR' }
# 如有匹配，移到 RunDisabled
```

### 批量发现遥测组件

```powershell
# 用关键词模式一次性扫描所有三个层面
$pattern = 'telemetry|CEIP|SQM|DiagTrack|esrv|QUEENCREEK|UsageReport|NvTelemetry'

Write-Host "`n=== 服务 ===" -ForegroundColor Cyan
Get-CimInstance Win32_Service |
    Where-Object { $_.Name -match $pattern -or $_.DisplayName -match $pattern } |
    Select-Object Name, DisplayName, StartMode, State |
    Format-Table -AutoSize

Write-Host "`n=== 计划任务 ===" -ForegroundColor Cyan
Get-ScheduledTask |
    Where-Object { $_.TaskName -match $pattern -or $_.TaskPath -match $pattern } |
    Select-Object TaskName, TaskPath, State |
    Format-Table -AutoSize

Write-Host "`n=== 启动项 (HKCU Run) ===" -ForegroundColor Cyan
$runKey = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
if ($runKey) {
    $runKey.PSObject.Properties |
        Where-Object { $_.Name -notmatch '^PS' -and $_.Value -match $pattern } |
        Select-Object Name, Value
}
```

---

## 验证

禁用后必须验证，否则不算完成。

```powershell
# 1. 重启后检查进程是否仍在运行
Get-Process | Where-Object { $_.ProcessName -match 'esrv|DiagTrack|telemetry' }
# 预期：无匹配结果

# 2. 检查服务状态
Get-CimInstance Win32_Service -Filter "Name='ESRV_SVC_QUEENCREEK'" |
    Select-Object Name, StartMode, State
# 预期：StartMode = Disabled, State = Stopped

# 3. 检查计划任务状态
Get-ScheduledTask -TaskName "*ESRV*" | Select-Object TaskName, State
# 预期：State = Disabled
```

### Windows Update 复活问题

部分 Microsoft 遥测组件（特别是 `DiagTrack`）会在 Windows 大版本更新后被重新启用。建议：
- 更新后重新运行扫描脚本复查
- 如有条件，通过组策略（`gpedit.msc`）设置遥测级别为 `Security`（最低），比逐个禁用服务更持久
