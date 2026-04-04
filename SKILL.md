---
name: win-sweep
description: "Windows system cleanup and optimization toolkit. Use when: Windows cleanup, 系统清理, 电脑太慢, 开机慢, 开机加速, C盘满了, 清理磁盘, 释放空间, 关掉没用的后台程序, 关闭开机自启, 卸载残留清理, 删掉偷偷上传数据的东西, 检查可疑进程, 清理没用的定时任务, 卸载软件, 彻底删除软件, 强力卸载, 清除残留, 卸载流氓软件, 删除360, 卸载鲁大师, 清理2345, 国产流氓软件, 主页被劫持, 浏览器主页锁定, 卸载McAfee, 卸载Norton, 删除屏保软件, 清理壁纸软件, 删除CCleaner, 假优化软件, 假驱动更新, scareware, uninstall software, force uninstall, remove bloatware, clean uninstall leftovers, remove Chinese bloatware, remove scareware, remove screensaver, disable services, disable startup items, reduce boot time, free disk space, uninstall leftovers, telemetry removal, suspicious service detection, scheduled task cleanup"
license: MIT
---

# win-sweep — Windows System Cleanup & Optimization

A skill for diagnosing and cleaning up Windows system bloat: redundant services, startup items, scheduled tasks, disk space hogs, and suspicious processes.

## When to Use

- System is slow or boot time is too long
- Low disk space (C: or D: drive)
- Too many startup items or background services
- Need to audit/disable telemetry components
- Found suspicious or leftover services
- Third-party software registered excessive auto-start services
- Leftover artifacts after software uninstallation

## Workflow

### Phase 1: Diagnosis (Safe — No Confirmation Needed)

Run the diagnostic script to assess system state. Diagnostic operations are read-only and never modify the system.

1. [System Overview](./scripts/diagnose.ps1) — Disk usage, installed software, startup items, services, scheduled tasks, memory usage ranking
2. Review output and identify optimization targets

### Phase 2: Optimization (Dangerous — Confirmation Required)

Execute targeted fixes based on diagnostic results. **All modification operations must follow the safety mechanisms below.**

1. [Service Optimization](./scripts/optimize-services.ps1) — Batch-modify service startup modes (Auto → Manual/Disabled)
2. [Startup Management](./scripts/manage-startups.ps1) — Disable startup items with backup to `RunDisabled` registry key
3. [Scheduled Task Cleanup](./scripts/clean-tasks.ps1) — Disable unnecessary scheduled tasks
4. [Suspicious Service Detection](./scripts/detect-suspicious.ps1) — Find leftover/unsigned/suspicious services
5. [Software Uninstall & Cleanup](./scripts/uninstall-software.ps1) — Uninstall programs via winget/native uninstaller, then scan and remove leftover services, tasks, startup items, directories, and registry entries

### Phase 3: Verification (Safe — No Confirmation Needed)

1. [Verification Script](./scripts/verify.ps1) — Confirm that changes have taken effect correctly
2. After reboot, re-run diagnostics to compare before/after

---

## Safety Mechanisms (Iron Rules)

### I. Operation Risk Levels

Different operations carry different risk levels and confirmation requirements.

| Level | Operation Type | Example | Reversibility | Confirmation |
|-------|---------------|---------|---------------|-------------|
| **Read-only** | Diagnosis, scan, query | `Get-CimInstance`, `Get-ScheduledTask` | — | None needed |
| **Low-risk** | Auto → Manual | Set service to on-demand startup | Reversible: change back to Auto | Summary table confirmation |
| **Medium-risk** | Auto → Disabled, disable scheduled tasks | Completely prevent startup | Reversible: change back to Auto/Enable | Summary table + impact notes |
| **High-risk** | Delete service, delete registry keys | `sc.exe delete`, remove startup items | **Backup required** for reversal | Per-item confirmation + backup proof |

### II. Confirmation Flow

#### Batch Operations (Low/Medium Risk): Summary Table Confirmation

When performing multiple same-level operations, present a summary table for one-time confirmation instead of asking one by one:

```
I recommend the following adjustments for N services:

| # | Service | Current State | Suggested Action | Purpose | Risk |
|---|---------|--------------|-----------------|---------|------|
| 1 | ServiceA | Auto/Running | → Manual | XX license service | Low |
| 2 | ServiceB | Auto/Stopped | → Disabled | XX telemetry | Low |
| ...

Notes:
- Manual services start automatically when the corresponding software is opened — no impact on daily use
- Can be reverted to Auto at any time

Proceed? You can also say "skip #2" to exclude specific items.
```

User can:
- Confirm all ("confirm", "go ahead", "yes")
- Exclude some ("skip #2 and #5")
- Reject all ("no", "cancel")

#### High-Risk Operations: Per-Item Confirmation + Backup

Delete operations must:
1. **Execute backup first** and inform the user of the backup location
2. **Report per item**: what it is, why deletion is recommended, consequences, rollback method
3. **Wait for user confirmation on each individual item**

```
⚠️ High-risk operation: Delete service "SuspiciousService"

- What: Leftover service whose executable C:\ProgramData\xxx.exe no longer exists
- Investigation: Risk score 7/12 (file not found +3, garbled service name +4)
- Backed up: Registry exported to %TEMP%\svc-backup-SuspiciousService.reg
- Rollback: reg import "%TEMP%\svc-backup-SuspiciousService.reg" + reboot
- Command: sc.exe delete "SuspiciousService"

Proceed?
```

### III. System Restore Point

**Before the first modification operation**, suggest that the user create a system restore point:

```
About to modify system configuration. Recommend creating a system restore point first, so you can roll back entirely if issues arise.

Command: Checkpoint-Computer -Description "win-sweep pre-optimization" -RestorePointType MODIFY_SETTINGS

Create now? (You can skip if you already have a recent restore point.)
```

If the user declines, note it but do not block subsequent operations — this is a recommendation, not a requirement.

### IV. Change Log

After each modification operation, record in terminal output:
- Timestamp
- Operation details (original value → new value)
- Command executed

This enables post-hoc auditing and troubleshooting.

---

## Core Principles

- **Prefer Manual over Disabled** — `start= demand` lets Windows start the service on demand; `start= disabled` completely prevents startup. Use Manual unless the service is telemetry or a discontinued product
- **Back up before modifying** — Move startup items to `RunDisabled` instead of deleting; `reg export` before deleting services
- **Three-layer telemetry sweep** — Must check services + scheduled tasks + startup items simultaneously; disabling only one layer is ineffective (see [telemetry.md](./references/telemetry.md))
- **Check what the service actually does** — Many games and third-party apps silently install always-on services (anti-cheat engines, game platform launchers, companion apps). During diagnosis, identify each service's actual purpose and whether it genuinely needs to run at boot. If the user only plays a game occasionally, its background service doesn't need to be Auto (see Pattern 9 & 10 in [service-rules.md](./references/service-rules.md))
- **Decision framework over hardcoded lists** — Reference docs provide universal identification patterns, not hardcoded service name lists. Apply the framework to unknown services rather than only matching known lists
- **Administrator privileges required** — Both diagnosis and modification benefit significantly from an elevated PowerShell session. **Without admin, diagnosis is incomplete**: service details (binary path, startup account, failure actions), HKLM startup items, scheduled task internals, and signature checks may fail or return partial data. The AI must detect the privilege level at the start of every session and, if not elevated, **proactively warn the user with a clear summary of what will be missing**:

  ```
  ⚠️ Current session does NOT have Administrator privileges.

  Impact on diagnosis:
  - Service binary paths and startup accounts: may be incomplete
  - HKLM startup items: cannot read
  - Scheduled task details: limited
  - Signature verification for some executables: may fail
  - Memory usage for system processes: hidden

  Impact on modifications:
  - Service optimization: will fail
  - HKLM startup items: cannot modify
  - Scheduled task cleanup: will fail
  - Software uninstall (system-level): will fail
  - Suspicious service deletion: will fail

  I can still run a partial diagnostic scan, but the results will be incomplete
  and I may miss important issues.

  Recommend: Restart [your tool] as Administrator for full access.
  [How to elevate: right-click the app icon → Run as administrator]
  ```

  Detection:
  ```powershell
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  ```
  If `$isAdmin` is `$false`, **always** display the warning above before proceeding. Do not silently continue. The user must make an informed decision about whether to proceed with limited results or restart with admin rights. See the "Administrator Privileges" section in the README.

## Reference Documents

Load on demand — read the relevant document only when encountering a specific issue. No need to preload everything.

- [Service Optimization Rules](./references/service-rules.md) — Decision framework: whether any service can be safely modified + universal pattern matching
- [Telemetry Identification & Removal](./references/telemetry.md) — Identification framework for telemetry components (keyword patterns + behavioral traits) + known vendor cases + three-layer disable templates
- [Suspicious Service Checklist](./references/suspicious-checklist.md) — Quantified risk scoring system (12 signals) + investigation workflow + decision matrix + false positive exclusion
- [PowerShell & sc.exe Gotchas](./references/sc-gotchas.md) — Common AI-generated PowerShell errors (`&&`, comparison operators, array unwrapping, etc.) + sc.exe-specific pitfalls + self-check list
- [Software Uninstall Guide](./references/uninstall-guide.md) — Decision framework for software removal + removal strategies (winget/MSI/native) + 6-area leftover cleanup checklist + bloatware patterns + edge cases (kernel drivers, UWP, anti-uninstall software)
