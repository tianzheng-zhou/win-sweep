#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep diagnostics — scan and report system status.
.DESCRIPTION
    Collects disk usage, installed software, startup items, services,
    scheduled tasks, and memory usage rankings, outputting a structured report.
.NOTES
    Full results require an elevated (Administrator) PowerShell session.
    Without admin privileges, some information will be skipped (service details, etc.).
#>

[CmdletBinding()]
param(
    [ValidateSet('All','System','Disk','Software','Startups','Services','Tasks','Memory')]
    [string[]]$Section = 'All'
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "`n" -NoNewline
    Write-Host ('!' * 60) -ForegroundColor Red
    Write-Host ' WARNING: Running WITHOUT Administrator privileges' -ForegroundColor Red
    Write-Host ('!' * 60) -ForegroundColor Red
    Write-Host @"

  The following information will be INCOMPLETE or MISSING:
    - Service binary paths and startup accounts
    - HKLM startup items
    - Scheduled task internal details
    - Signature verification for some executables
    - Full memory usage for system processes

  For a complete diagnosis, restart your tool as Administrator.
  (Right-click the app icon -> Run as administrator)

  Proceeding with partial results...
"@ -ForegroundColor Yellow
    Write-Host ('!' * 60) -ForegroundColor Red
    Write-Host ''
}

function Write-Section([string]$Title) {
    Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "$('=' * 60)" -ForegroundColor Cyan
}

$runAll = $Section -contains 'All'

# ── System Info ──
if ($runAll -or $Section -contains 'System') {
    Write-Section 'System Info'
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

# ── Disk Usage ──
if ($runAll -or $Section -contains 'Disk') {
    Write-Section 'Disk Usage'
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{N='SizeGB';    E={[math]::Round($_.Size / 1GB, 1)}},
            @{N='FreeGB';    E={[math]::Round($_.FreeSpace / 1GB, 1)}},
            @{N='UsedGB';    E={[math]::Round(($_.Size - $_.FreeSpace) / 1GB, 1)}},
            @{N='UsedPct';   E={[math]::Round(($_.Size - $_.FreeSpace) / $_.Size * 100, 1)}} |
        Format-Table -AutoSize

    # C: drive top-level directory sizes (top 15)
    Write-Host "`nC:\ Top-Level Directory Sizes (Top 15):" -ForegroundColor Yellow
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

# ── Installed Software ──
if ($runAll -or $Section -contains 'Software') {
    Write-Section 'Installed Software (Top 30 by size)'
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

# ── Startup Items ──
if ($runAll -or $Section -contains 'Startups') {
    Write-Section 'Startup Items'

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

    # RunDisabled (backed-up startup items)
    $disPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunDisabled'
    if (Test-Path $disPath) {
        Write-Host "`nHKCU\RunDisabled (disabled backups):" -ForegroundColor Yellow
        (Get-ItemProperty $disPath -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$' } |
            ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Command=$_.Value } } |
            Format-Table -AutoSize -Wrap
    }
}

# ── Services ──
if ($runAll -or $Section -contains 'Services') {
    Write-Section 'Auto-Start Services (non-svchost first)'
    $services = Get-CimInstance Win32_Service -Filter "StartMode='Auto'" |
        Select-Object Name, DisplayName, State, StartName,
            @{N='BinaryPath'; E={
                # Truncate to first 80 chars for readability
                $p = $_.PathName
                if ($p.Length -gt 80) { $p.Substring(0, 77) + '...' } else { $p }
            }},
            @{N='IsSvchost'; E={ $_.PathName -match 'svchost\.exe' }}

    Write-Host "`nNon-svchost auto-start services ($($services | Where-Object {-not $_.IsSvchost} | Measure-Object | Select-Object -ExpandProperty Count)):" -ForegroundColor Yellow
    $services | Where-Object { -not $_.IsSvchost } |
        Sort-Object Name |
        Select-Object Name, DisplayName, State, StartName, BinaryPath |
        Format-Table -AutoSize -Wrap

    Write-Host "`nsvchost-hosted auto-start services ($($services | Where-Object {$_.IsSvchost} | Measure-Object | Select-Object -ExpandProperty Count)):" -ForegroundColor Yellow
    $services | Where-Object { $_.IsSvchost } |
        Sort-Object Name |
        Select-Object Name, DisplayName, State, StartName |
        Format-Table -AutoSize
}

# ── Scheduled Tasks ──
if ($runAll -or $Section -contains 'Tasks') {
    Write-Section 'Enabled Non-Microsoft Scheduled Tasks'
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

# ── Memory Usage ──
if ($runAll -or $Section -contains 'Memory') {
    Write-Section 'Memory Usage Top 30 (non-system processes)'
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

Write-Host "`nDiagnostics complete." -ForegroundColor Green
