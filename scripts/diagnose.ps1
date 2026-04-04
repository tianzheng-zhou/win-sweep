#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep 系统诊断 — 扫描并报告系统状态。
.DESCRIPTION
    收集磁盘用量、已安装软件、启动项、服务、
    计划任务、内存占用排行等信息，输出结构化报告。
.NOTES
    完整结果需要管理员权限的 PowerShell。
    无管理员权限时部分信息会跳过（服务详细信息等）。
#>

[CmdletBinding()]
param(
    [ValidateSet('All','System','Disk','Software','Startups','Services','Tasks','Memory')]
    [string[]]$Section = 'All'
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

function Write-Section([string]$Title) {
    Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "$('=' * 60)" -ForegroundColor Cyan
}

$runAll = $Section -contains 'All'

# ── 系统信息 ──
if ($runAll -or $Section -contains 'System') {
    Write-Section '系统信息'
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    [PSCustomObject]@{
        ComputerName  = $cs.Name
        OS            = $os.Caption
        Build         = $os.BuildNumber
        InstallDate   = $os.InstallDate
        LastBoot      = $os.LastBootUpTime
        Uptime        = ((Get-Date) - $os.LastBootUpTime).ToString('d\.hh\:mm\:ss')
        TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        FreeMemoryGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        AdminSession  = $isAdmin
    } | Format-List
}

# ── 磁盘用量 ──
if ($runAll -or $Section -contains 'Disk') {
    Write-Section '磁盘用量'
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{N='SizeGB';    E={[math]::Round($_.Size / 1GB, 1)}},
            @{N='FreeGB';    E={[math]::Round($_.FreeSpace / 1GB, 1)}},
            @{N='UsedGB';    E={[math]::Round(($_.Size - $_.FreeSpace) / 1GB, 1)}},
            @{N='UsedPct';   E={[math]::Round(($_.Size - $_.FreeSpace) / $_.Size * 100, 1)}} |
        Format-Table -AutoSize

    # C 盘顶层目录大小（前 15）
    Write-Host "`nC:\ 顶层目录大小 (Top 15):" -ForegroundColor Yellow
    Get-ChildItem C:\ -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{
                Directory = $_.Name
                SizeGB    = [math]::Round($size / 1GB, 2)
            }
        } |
        Sort-Object SizeGB -Descending | Select-Object -First 15 |
        Format-Table -AutoSize
}

# ── 已安装软件 ──
if ($runAll -or $Section -contains 'Software') {
    Write-Section '已安装软件 (Top 30 by size)'
    $regPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $regPaths | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() } |
        Select-Object DisplayName, DisplayVersion, Publisher,
            @{N='SizeMB'; E={[math]::Round($_.EstimatedSize / 1024, 1)}} |
        Sort-Object SizeMB -Descending | Select-Object -First 30 |
        Format-Table -AutoSize
}

# ── 启动项 ──
if ($runAll -or $Section -contains 'Startups') {
    Write-Section '启动项'

    $runKeys = @(
        @{ Scope='HKCU'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Scope='HKLM'; Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' }
    )
    foreach ($k in $runKeys) {
        Write-Host "`n$($k.Scope)\Run:" -ForegroundColor Yellow
        $props = Get-ItemProperty $k.Path -ErrorAction SilentlyContinue
        if ($props) {
            $props.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$' } |
                ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Command=$_.Value } } |
                Format-Table -AutoSize -Wrap
        } else {
            Write-Host '  (empty)'
        }
    }

    # RunDisabled（已备份的启动项）
    $disPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunDisabled'
    if (Test-Path $disPath) {
        Write-Host "`nHKCU\RunDisabled (已禁用的备份):" -ForegroundColor Yellow
        (Get-ItemProperty $disPath -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$' } |
            ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Command=$_.Value } } |
            Format-Table -AutoSize -Wrap
    }
}

# ── 服务 ──
if ($runAll -or $Section -contains 'Services') {
    Write-Section '自动启动服务 (非 svchost 优先)'
    $services = Get-CimInstance Win32_Service -Filter "StartMode='Auto'" |
        Select-Object Name, DisplayName, State, StartName,
            @{N='BinaryPath'; E={
                # 取前 80 个字符，方便阅读
                $p = $_.PathName
                if ($p.Length -gt 80) { $p.Substring(0, 77) + '...' } else { $p }
            }},
            @{N='IsSvchost'; E={ $_.PathName -match 'svchost\.exe' }}

    Write-Host "`n非 svchost 自动启动服务 ($($services | Where-Object {-not $_.IsSvchost} | Measure-Object | Select-Object -ExpandProperty Count) 个):" -ForegroundColor Yellow
    $services | Where-Object { -not $_.IsSvchost } |
        Sort-Object Name |
        Select-Object Name, DisplayName, State, StartName, BinaryPath |
        Format-Table -AutoSize -Wrap

    Write-Host "`nsvchost 托管的自动启动服务 ($($services | Where-Object {$_.IsSvchost} | Measure-Object | Select-Object -ExpandProperty Count) 个):" -ForegroundColor Yellow
    $services | Where-Object { $_.IsSvchost } |
        Sort-Object Name |
        Select-Object Name, DisplayName, State, StartName |
        Format-Table -AutoSize
}

# ── 计划任务 ──
if ($runAll -or $Section -contains 'Tasks') {
    Write-Section '已启用的非微软计划任务'
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' } |
        Select-Object TaskName, TaskPath, State,
            @{N='Actions'; E={
                ($_.Actions | ForEach-Object {
                    if ($_.Execute) { $_.Execute + ' ' + $_.Arguments }
                }) -join '; '
            }} |
        Sort-Object TaskPath, TaskName |
        Format-Table -AutoSize -Wrap
}

# ── 内存占用 ──
if ($runAll -or $Section -contains 'Memory') {
    Write-Section '内存占用 Top 30 (非系统进程)'
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -notmatch '^(Idle|System|Registry|Memory Compression|smss|csrss|wininit|winlogon|services|lsass|svchost)$' } |
        Sort-Object WorkingSet64 -Descending | Select-Object -First 30 |
        Select-Object @{N='PID';E={$_.Id}},
            ProcessName,
            @{N='MemMB'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
            @{N='Path'; E={
                $p = $_.Path
                if ($p -and $p.Length -gt 60) { $p.Substring(0, 57) + '...' } else { $p }
            }} |
        Format-Table -AutoSize
}

Write-Host "`n诊断完成。" -ForegroundColor Green
