# Software Uninstall & Leftover Cleanup Guide

This document provides a **decision framework** for the AI to evaluate software removal requests and ensure thorough cleanup.
The goal is not just running the uninstaller, but eliminating all residual artifacts that accumulate over time.

---

## Core Principles

1. **Uninstaller first, manual cleanup second** — Always try the software's own uninstaller (or winget) before manually deleting files. Native uninstallers handle driver removal, COM registration, file associations, and other hooks that manual deletion misses.
2. **winget over native when available** — `winget uninstall` often invokes the quiet/silent uninstaller with correct flags, handles edge cases, and is more scriptable.
3. **Leftover scan is mandatory after uninstall** — Every uninstaller leaves something behind. Always run a cleanup scan after the uninstaller finishes.
4. **Batch cleanup needs the same safety mechanisms** — Leftover deletion follows the same risk levels and confirmation flow as service optimization (see SKILL.md Safety Mechanisms).

---

## Decision Framework: Should This Software Be Removed?

When the user asks to clean up software or free disk space, evaluate in this order:

```
1. Is this a system-critical component?
   → Windows Features, drivers for active hardware, .NET runtimes in use, VC++ Redistributables → Do NOT remove
   → Continue

2. Is it security software actively protecting the system?
   → Antivirus, firewall, disk encryption → Warn user; only proceed with explicit confirmation
   → Continue

3. Is it bloatware/bundleware the user didn't intentionally install?
   → Browser toolbars, "free" utilities bundled with other software, OEM trialware → Recommend removal
   → Continue

4. Is it software the user no longer uses?
   → Check last-used date if available; ask user if uncertain
   → Recommend removal

5. Is it a duplicate (e.g., two PDF readers, two media players)?
   → Recommend keeping one, removing the other
   → Continue

6. Does it have a large footprint vs. usage frequency?
   → Large (>500MB) + rarely used → Recommend removal or at least inform user of size
```

---

## Do Not Remove (Hard Rules)

| Category | Examples | Reason |
|----------|----------|--------|
| Visual C++ Redistributables | `Microsoft Visual C++ 20xx Redistributable` | Many applications silently depend on these; removing causes crashes |
| .NET Runtimes | `.NET Framework`, `.NET Desktop Runtime` | Same reason — silent dependencies |
| Windows SDK / Build Tools | `Windows SDK`, `Build Tools` | Development dependencies |
| Active hardware drivers | GPU drivers (NVIDIA/AMD/Intel), audio drivers, network drivers | Hardware stops working |
| Currently running security software | Windows Defender components, third-party AV | Leaves system unprotected |
| Windows Features | Hyper-V, WSL, Windows Sandbox | Use `optionalfeatures.exe` or `DISM`, not uninstall |

### Guiding Principle
If the software has no visible entry in `Programs and Features` / `Apps & Features` but shows up in the registry, it's likely a component dependency — investigate before removing.

---

## Removal Strategies (Ordered by Preference)

### Strategy 1: winget (Best)
```powershell
winget uninstall --name "Software Name" --silent --accept-source-agreements
```
**Pros**: Handles silent flags, consistent behavior, scriptable.
**Cons**: Not all software is in the winget repository.
**Check availability**: `winget list --name "Software Name"`

### Strategy 2: Native Quiet Uninstaller
```powershell
# From QuietUninstallString in registry
& "C:\Program Files\Vendor\uninstall.exe" /S /silent /quiet
```
**Pros**: Vendor-intended removal path.
**Cons**: Not all software provides a quiet option; flags vary wildly (`/S`, `/silent`, `/quiet`, `/VERYSILENT`, `/qn`).

### Strategy 3: MSI Uninstall
```powershell
msiexec.exe /x {PRODUCT-GUID} /quiet /norestart
```
**Pros**: Standardized for MSI-installed software.
**Cons**: Only works for MSI packages; GUID must be extracted from registry.

### Strategy 4: Native Interactive Uninstaller (Fallback)
```powershell
# From UninstallString in registry
Start-Process "C:\Program Files\Vendor\uninstall.exe" -Wait
```
**Cons**: Requires user interaction; may show ads or "are you sure" dialogs.

---

## Leftover Cleanup Checklist

After the uninstaller completes, scan these 6 areas:

### 1. Registry Uninstall Entries
- `HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*`
- `HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*`
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*`

If the entry still exists after uninstall → orphaned registry entry → safe to remove.

### 2. Orphaned Services
Services whose executable points to a path under the uninstalled software's directory.
```powershell
Get-CimInstance Win32_Service | Where-Object { $_.PathName -like "*SoftwareName*" }
```
→ Stop and delete (`sc.exe stop`, `sc.exe delete`). **Back up registry key first.**

### 3. Orphaned Scheduled Tasks
```powershell
Get-ScheduledTask | Where-Object { 
    $_.TaskName -like "*SoftwareName*" -or 
    ($_.Actions.Execute -like "*SoftwareName*") 
}
```
→ Unregister.

### 4. Startup Items
Check both `Run` and `RunDisabled` keys in HKCU and HKLM.

### 5. Filesystem Leftovers
Common locations:
| Path | Type |
|------|------|
| `%ProgramFiles%\Vendor\` | Main program directory |
| `%ProgramFiles(x86)%\Vendor\` | 32-bit program directory |
| `%ProgramData%\Vendor\` | Shared application data |
| `%LOCALAPPDATA%\Vendor\` | Per-user local data |
| `%APPDATA%\Vendor\` | Per-user roaming data |
| `%LOCALAPPDATA%\Programs\Vendor\` | Per-user installed programs |
| `%TEMP%\Vendor*` | Temporary files |

**Warning**: Match by vendor/product name, not just any substring. `Adobe` cleanup should not touch `AdobeRGB` ICC profiles on the system.

### 6. Application-Specific Registry Data
Some applications store settings in their own registry hives:
- `HKCU:\Software\Vendor\`
- `HKLM:\Software\Vendor\`

These are low priority — they don't cause performance impact. Only clean if the user wants a truly thorough removal.

---

## Common Bloatware Patterns

These patterns help identify software candidates for removal during a cleanup session.

### OEM Preinstalled Software
**Traits**: Publisher matches the PC manufacturer (HP, Dell, Lenovo, Acer, ASUS); often includes "Support", "Experience", "Welcome", "Registration"
**Examples**: HP Support Assistant, Dell SupportAssist, Lenovo Vantage, MyASUS, Acer Care Center
**Judgment**: Keep one management utility if the user wants driver updates; the rest (registration, offers, "experience" apps) can go

### Bundleware / PUPs (Potentially Unwanted Programs)
**Traits**: Software the user doesn't remember installing; appeared alongside another installer; browser toolbars; "optimizer" or "cleaner" tools; names containing "toolbar", "optimizer", "booster", "driver updater"
**Examples**: McAfee WebAdvisor (bundled), WinZip Driver Updater, Segurazo, ByteFence, PC Optimizer Pro
**Judgment**: Strong removal recommendation. Many of these are borderline malware.

### Western Rogue Software / Scareware
**Traits**: Aggressive pop-ups warning about "thousands of errors" or "PC at risk" to scare users into purchasing; fake scan results; auto-start with persistent tray notifications; difficult to uninstall cleanly; often bundled with free downloads. Unlike Chinese rogue software which relies on guardian processes, Western rogue software relies more on scare tactics and dark UX patterns.
**Known categories and families**:

#### Fake System Optimizers / Registry Cleaners
Software that claims to "fix" or "optimize" your PC but provides zero real benefit. Windows has no meaningful "registry errors" — these products invent problems to sell solutions.

| Software | Common Residuals | Notes |
|----------|------------------|-------|
| CCleaner (post-Avast acquisition) | `CCleaner\`, `CCleanerBrowser\`, `Piriform\`, services: `CCleanerPerformanceOptimizerService`, `ccleaner` scheduled tasks | Was once legitimate; now bundles its own browser, pushes paid upgrades with pop-ups, and includes a "performance optimizer" background service. Free version is still semi-useful for temp file cleanup but the background services are unnecessary |
| Advanced SystemCare / IObit products | `IObit\`, `ASC.exe`, `AdvancedSystemCare\`, services: `LiveUpdateSvc`, `AdvancedSystemCareService` | Entire IObit suite (Driver Booster, Uninstaller, Malware Fighter) acts as a bundleware ecosystem — installing one pushes the others |
| Glary Utilities | `Glarysoft\`, `GlaryUtilities\`, scheduled tasks | Less aggressive but still a fake optimizer |
| Auslogics BoostSpeed | `Auslogics\`, `BoostSpeed\`, scheduled tasks, services | Installs multiple background services; aggressive upgrade nags |
| Reimage Repair / Restoro / Fortect | Services with `Reimage` or `Restoro`, pop-up scan windows | Classic scareware — runs a fake "scan" then demands payment to "fix" issues. Often arrives via deceptive web ads |
| MyCleanPC / SlimCleaner Plus | Background services, persistent tray icons | Pure scareware |

#### Fake Driver Updaters
Windows Update + manufacturer websites handle drivers perfectly. These tools create fake "outdated driver" warnings.

| Software | Common Residuals | Notes |
|----------|------------------|-------|
| Driver Booster (IObit) | `IObit\Driver Booster\`, `DBService`, scheduled tasks | Part of the IObit ecosystem; bundles other IObit products |
| DriverPack Solution | `DriverPack\`, temp extraction folders (can be several GB) | Known for bundling adware during "driver installation" |
| Driver Easy | `Driver Easy\`, `DriverEasy` service | Freemium model with aggressive upgrade prompts |
| SlimDrivers / SlimWare | `SlimWare\` | Bundleware |

#### Bloated Antivirus / Security Software
Legitimate security software that has become excessively bloated, difficult to remove, or is aggressively bundled.

| Software | Common Residuals | Notes |
|----------|------------------|-------|
| McAfee (pre-installed) | `McAfee\`, multiple services (`McAfee*`, `masvc`, `mfemms`, `McpService`), kernel drivers, firewall hooks, browser extensions | Notoriously pre-installed on OEM machines; very difficult to fully remove. **Use the official [McAfee Consumer Product Removal Tool (MCPR)](https://www.mcafee.com/consumer/en-us/store/m0/catalog/mtp_559/mcafee-total-protection.html)** — standard uninstall often leaves service remnants |
| Norton (pre-installed) | `Norton\`, `Symantec\`, multiple services (`N360`, `Norton*`), kernel drivers | Pre-installed on many OEM machines. **Use [Norton Remove and Reinstall Tool](https://support.norton.com/sp/static/external/tools/nrnr.exe)** for clean removal |
| Avast / AVG | `Avast Software\`, `AVG\`, services (`AvastSvc`, `aswbIDSAgent`), kernel drivers, browser extensions | Once reputable, now shows pop-up ads for VPN/password manager/driver updater upsells. Use official [Avast Uninstall Utility](https://support.avast.com/en-ww/article/Antivirus-uninstall-utility/) in Safe Mode |
| Kaspersky | `Kaspersky Lab\`, multiple services, network filter drivers | Functional but heavy. If removing, use official [Kaspersky Removal Tool (kavremover)](https://support.kaspersky.com/common/uninstall/1464) |

#### Browser Toolbars & Search Hijackers
**Traits**: Modifies browser homepage, default search engine, or new tab page. Names contain "toolbar", "search", "newtab". Often bundled via "Recommended" checkboxes in other installers.

| Software | Common Residuals | Notes |
|----------|------------------|-------|
| Ask Toolbar / Ask.com | `AskPartnerNetwork\`, browser extensions | Classic bundleware; often rides with Java installer |
| Conduit / Search Protect | `Conduit\`, `SearchProtect\`, services | Aggressive browser hijacker; replaces homepage and search engine |
| Mindspark / MyWay toolbars | Various `*Toolbar\` directories, browser extensions with random-looking names | Dozens of variants (iLivid, FromDocToPDF, EasyDirectionsFinder, etc.) |
| Web Companion (Lavasoft/Adaware) | `Lavasoft\Web Companion\`, service, startup entry | Ironic: an "ad-aware" product that itself behaves like adware |

**Judgment for all Western rogue software**: **Recommend removal.** Replace with built-in Windows tools:
- **System optimization**: Not needed — Windows manages itself. If disk is full, use Windows Disk Cleanup (`cleanmgr`) or Storage Sense.
- **Driver updates**: Windows Update + manufacturer website (e.g., NVIDIA/AMD/Intel download pages).
- **Antivirus**: Windows Defender (built-in) is sufficient for most users.
- **Registry cleaning**: Never needed — the Windows registry is not a performance bottleneck.

### Screensaver Software
**Traits**: Installs `.scr` files, background services for wallpaper rotation or "live wallpaper" effects, system tray agents. Names contain "screensaver", "wallpaper", "desktop enhancement", "live desktop". Often includes ad delivery mechanisms or data collection.
**Why remove**: Modern LCD, LED, and OLED displays do not suffer from burn-in the way CRT monitors did (OLED has a different type of burn-in that screensavers don't help with — static screensaver elements can actually make it worse). Screensaver software is an obsolete category that now primarily serves as a vehicle for adware, pop-ups, and background resource consumption. Windows' built-in lock screen and power settings (turn off display after N minutes) provide all the functionality needed.
**Known examples**:

| Software | Common Residuals | Notes |
|----------|------------------|-------|
| Screensaver Planet / Screensavers Planet | `.scr` files in `C:\Windows\`, background service | Ad-supported; installs sponsored screensavers |
| Wallpaper Engine | `wallpaper_engine\`, Steam service | Legitimate (Steam app) but consumes significant GPU/CPU resources when active. Not rogue, but worth mentioning if user is looking for performance gains — suggest disabling auto-start |
| PUSH Video Wallpaper | `PUSH Entertainment\`, startup entry | Background video rendering consumes resources |
| Desktop Live Wallpapers (various) | Startup entries, background processes, `.scr` files | Many free variants exist; most are ad-supported |
| 小鸟壁纸 / BirdWallpaper | (See Chinese Rogue Software section) | |
| 火萤视频桌面 / Huoying | `Huoying\`, startup service | Similar to 小鸟壁纸; Chinese market; ad-driven |
| 搜狗壁纸 / Sogou Wallpaper | `SogouWallpaper\`, `SogouExplorer\` residuals | Often bundled with 搜狗输入法 |
| 猎豹轻桌面 / CM Launcher (desktop) | `cmcm\`, startup entries | Cheetah Mobile ecosystem; primarily ad delivery |

**Judgment**: **Recommend removal of all screensaver/live wallpaper software** unless the user explicitly values the feature and understands the resource cost. Replace with:
- **Lock screen**: Windows built-in lock screen (Settings → Personalization → Lock screen)
- **Power saving**: Settings → System → Power & sleep → Turn off screen after N minutes
- **Wallpaper slideshow**: Settings → Personalization → Background → Slideshow (built-in, zero overhead)

### Abandoned / EOL Software
**Traits**: Software no longer maintained by the vendor; known EOL dates passed; no security updates
**Examples**: Adobe Flash Player, Internet Explorer components, Silverlight, Java 6/7/8 (if not needed by specific applications)
**Judgment**: Recommend removal — security liability with zero value.

### Duplicate Functionality
**Traits**: Two or more programs doing the same thing
**Common overlaps**: Multiple PDF readers, multiple media players, multiple archive tools, multiple screenshot tools
**Judgment**: Help user pick one; remove the rest.

### Chinese Rogue Software (国产流氓软件)
**Traits**: Aggressive self-protection (guardian processes that respawn each other), silent installation of additional software ("software bundling" / 捆绑安装), browser homepage hijacking, kernel-level drivers that block uninstallation, fake "uninstall" that only hides the UI, desktop shortcut spam, pop-up ads from system tray. Often installs other rogue software from the same ecosystem without user consent.
**Known families and their typical components**:

| Software | Publisher / Ecosystem | Common Residuals | Special Notes |
|----------|----------------------|------------------|---------------|
| 360安全卫士 / 360 Total Security | Qihoo 360 | `ZhuDongFangYu` (主动防御) driver, `360Tray.exe`, `360Safe.exe`, `HKLM:\Software\360Safe\`, services: `360rp`, `ZhuDongFangYu`, multiple scheduled tasks | Installs kernel filter driver; has guardian processes — must kill all 360 processes before uninstall. May need Safe Mode. Official removal tool: 360's own uninstaller invoked from Add/Remove Programs |
| 360浏览器 | Qihoo 360 | `360Chrome`, `360se6\`, browser homepage lock registry keys | Often bundled with 360安全卫士; hijacks default browser and homepage settings |
| 鲁大师 / LuDaShi | Qihoo 360 ecosystem | `ComputerZ_CN\`, services with `LuDaShi` or `ComputerZ`, `LudashiService`, startup items, desktop shortcuts to partner apps | Installs silently via 360 ecosystem; known to install additional software (e.g., wallpaper apps, game launchers) without consent |
| 小鸟壁纸 / BirdWallpaper | Qihoo 360 ecosystem | `BirdWallpaper\`, `Qiyi\`, startup service, scheduled tasks for ad delivery | Often installed silently by 鲁大师 or other 360-ecosystem software |
| 2345系列 (2345浏览器/好压/看图王) | 2345.com | `2345Explorer\`, `2345Pic\`, `HaoZip\`, homepage hijacking via `HKCU:\Software\Microsoft\Internet Explorer\Main\Start Page`, `Protect2345` service | Notorious homepage hijacker; `Protect2345` service actively re-hijacks browser homepage after user changes it |
| 金山毒霸 / Kingsoft Antivirus | Kingsoft / Cheetah | `kxescore` service, `ksafe\`, `KSafeTray.exe`, kernel drivers | Guardian process architecture similar to 360; official removal tool recommended |
| 腾讯电脑管家 / Tencent PC Manager | Tencent | `QQPCMgr\`, `QQPCRTP\`, `QQPCTray.exe`, `QPCore` service | Less aggressive than 360 but still has guardian processes |
| 百度系 (百度杀毒/百度卫士/百度输入法) | Baidu | `BaiduSd\`, `BaiduProtect` service, `BaiduYun\`, input method service | 百度杀毒/卫士 already discontinued but leftovers persist; 百度输入法 has background data collection |
| 驱动精灵 / DriverGenius | Driver Talent | `DriverGenius\`, `DGService`, startup entries | Bundleware installer; pushes "recommended software" during driver updates |
| 驱动人生 / DTL | Driver Talent | `dtl\`, `DTLService`, scheduled tasks | Similar to 驱动精灵; aggressive ad popups |
| 快压 / KuaiZip | Various | `KuaiZip\`, file association hijacking | Hijacks archive file associations; hard to fully remove defaults |

**Judgment**: **Strong removal recommendation for all.** These programs provide little to no genuine value that isn't already covered by Windows built-in features or reputable alternatives. Their self-protection mechanisms and bundling behavior make them actively harmful.

**Removal strategy for guardian-process software (360, 金山, 腾讯管家)**:
1. Open Task Manager → End ALL processes from that vendor (they respawn each other — kill them in rapid succession, or use `taskkill /F /IM process.exe` in a script)
2. Run the software's own uninstaller from Add/Remove Programs (NOT from the software's UI "uninstall" — some have a fake option that just hides it)
3. If the uninstaller fails or is blocked, boot into **Safe Mode** and retry
4. After uninstall, run Cleanup to catch the inevitable leftovers: orphaned drivers, services, scheduled tasks, registry keys
5. Check browser homepage and default browser settings — they are likely hijacked
6. Check `HKLM:\SYSTEM\CurrentControlSet\Services\` for leftover kernel drivers (e.g., `ZhuDongFangYu`, `KSafeFilter`) — disable or delete

**Removal strategy for homepage hijackers (2345, 360浏览器)**:
1. Uninstall the software
2. Check and fix these registry keys:
   - `HKCU:\Software\Microsoft\Internet Explorer\Main\Start Page`
   - `HKLM:\Software\Microsoft\Internet Explorer\Main\Start Page`
   - `HKCU:\Software\Microsoft\Internet Explorer\Main\Default_Page_URL`
   - Browser-specific profile settings (Chrome: `Preferences` JSON; Edge: similar)
3. Remove any `Protect*` services (e.g., `Protect2345`) that actively re-hijack settings
4. Check scheduled tasks for re-hijack triggers

---

## Edge Cases

- **Software with kernel drivers** (anti-cheat, VPN, virtualization): The uninstaller must handle driver removal. If the uninstaller fails, do NOT manually delete driver files — this can cause BSOD. Escalate to the vendor's manual removal tool.
- **Software that resists uninstallation** (some AV products, malware, Chinese rogue software with guardian processes): Use the vendor's official removal tool (e.g., Norton Remove and Reinstall, Kaspersky Removal Tool, ESET Uninstaller). For Chinese rogue software (360, 金山, etc.), kill all vendor processes first, then uninstall; if blocked, boot into Safe Mode. See the "Chinese Rogue Software" pattern above for detailed steps.
- **UWP / Microsoft Store apps**: Use `Get-AppxPackage` / `Remove-AppxPackage`, not the registry-based uninstall flow.
- **Windows Features**: Use `Disable-WindowsOptionalFeature` or `DISM /Online /Disable-Feature`, not software uninstall.
- **Multiple versions of the same software** (e.g., Python 3.9 + 3.11): Confirm which version(s) the user wants to keep before removing any.
