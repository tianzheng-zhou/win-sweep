#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep 变更验证 — 确认优化变更已正确生效。
.DESCRIPTION
    重新扫描服务、启动项和计划任务，验证预期变更是否生效。
    可以对比备份 CSV 文件检测差异。
.PARAMETER BackupCsv
    optimize-services.ps1 生成的备份 CSV 文件路径（可选）。
    提供时会对比修改前后的差异。
.PARAMETER CheckServices
    要验证的服务列表（JSON 格式），格式同 optimize-services.ps1。
    示例: '[{"Name":"DiagTrack","Target":"Disabled"}]'
.PARAMETER CheckTasks
    要验证的计划任务名称数组，预期全部为 Disabled 状态。
.PARAMETER CheckStartups
    要验证已从 Run 移除的启动项名称数组。
#>

[CmdletBinding()]
param(
    [string]$BackupCsv,
    [string]$CheckServices,
    [string[]]$CheckTasks,
    [string[]]$CheckStartups
)

$hasWork = $false
$passCount = 0
$failCount = 0

# ── 服务验证 ──
if ($CheckServices) {
    $hasWork = $true
    $svcList = $CheckServices | ConvertFrom-Json
    Write-Host "`n=== 服务状态验证 ===" -ForegroundColor Cyan

    foreach ($item in $svcList) {
        $current = Get-CimInstance Win32_Service -Filter "Name='$($item.Name)'" -ErrorAction SilentlyContinue
        if (-not $current) {
            Write-Host "  [?] $($item.Name) — 服务不存在" -ForegroundColor DarkYellow
            continue
        }

        $expected = switch ($item.Target) {
            'Manual'   { 'Manual' }
            'Disabled' { 'Disabled' }
            'Auto'     { 'Auto' }
        }

        if ($current.StartMode -eq $expected) {
            Write-Host "  [PASS] $($item.Name) = $($current.StartMode)" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  [FAIL] $($item.Name) — 预期 $expected, 实际 $($current.StartMode)" -ForegroundColor Red
            $failCount++
        }
    }
}

# ── 计划任务验证 ──
if ($CheckTasks -and $CheckTasks.Count -gt 0) {
    $hasWork = $true
    Write-Host "`n=== 计划任务状态验证 ===" -ForegroundColor Cyan

    foreach ($taskName in $CheckTasks) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "  [?] $taskName — 任务不存在" -ForegroundColor DarkYellow
            continue
        }

        if ($task.State -eq 'Disabled') {
            Write-Host "  [PASS] $taskName = Disabled" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  [FAIL] $taskName — 预期 Disabled, 实际 $($task.State)" -ForegroundColor Red
            $failCount++
        }
    }
}

# ── 启动项验证 ──
if ($CheckStartups -and $CheckStartups.Count -gt 0) {
    $hasWork = $true
    Write-Host "`n=== 启动项验证 ===" -ForegroundColor Cyan

    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $disPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunDisabled'

    foreach ($name in $CheckStartups) {
        $inRun = $false
        $inDisabled = $false
        try { $null = (Get-ItemProperty $runPath -Name $name -ErrorAction Stop); $inRun = $true } catch {}
        try { $null = (Get-ItemProperty $disPath -Name $name -ErrorAction Stop); $inDisabled = $true } catch {}

        if (-not $inRun -and $inDisabled) {
            Write-Host "  [PASS] '$name' — 已从 Run 移到 RunDisabled" -ForegroundColor Green
            $passCount++
        } elseif ($inRun) {
            Write-Host "  [FAIL] '$name' — 仍在 Run 中（未禁用）" -ForegroundColor Red
            $failCount++
        } else {
            Write-Host "  [?] '$name' — 在 Run 和 RunDisabled 中均不存在" -ForegroundColor DarkYellow
        }
    }
}

# ── 备份对比 ──
if ($BackupCsv) {
    $hasWork = $true
    Write-Host "`n=== 服务配置对比 (vs 备份) ===" -ForegroundColor Cyan

    if (-not (Test-Path $BackupCsv)) {
        Write-Error "备份文件不存在: $BackupCsv"
    } else {
        $before = Import-Csv $BackupCsv
        $changed = @()

        foreach ($old in $before) {
            $current = Get-CimInstance Win32_Service -Filter "Name='$($old.Name)'" -ErrorAction SilentlyContinue
            if ($current -and $current.StartMode -ne $old.StartMode) {
                $changed += [PSCustomObject]@{
                    Name    = $old.Name
                    Before  = $old.StartMode
                    After   = $current.StartMode
                    State   = $current.State
                }
            }
        }

        if ($changed.Count -gt 0) {
            Write-Host "  $($changed.Count) 个服务发生了启动模式变化:" -ForegroundColor Yellow
            $changed | Format-Table -AutoSize
        } else {
            Write-Host "  无变化（所有服务启动模式与备份一致）。" -ForegroundColor DarkGray
        }
    }
}

# ── 无参数时显示快速概览 ──
if (-not $hasWork) {
    Write-Host "快速系统概览 — 当前状态:" -ForegroundColor Cyan

    $autoSvc = (Get-CimInstance Win32_Service -Filter "StartMode='Auto'" | Measure-Object).Count
    $runningSvc = (Get-CimInstance Win32_Service -Filter "State='Running'" | Measure-Object).Count
    Write-Host "  服务: $autoSvc 个 Auto, $runningSvc 个 Running"

    $runEntries = 0
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
      'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run') | ForEach-Object {
        $props = Get-ItemProperty $_ -ErrorAction SilentlyContinue
        if ($props) {
            $runEntries += ($props.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$' }).Count
        }
    }
    Write-Host "  启动项: $runEntries 个 (HKCU+HKLM Run)"

    $enabledTasks = (Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' } |
        Measure-Object).Count
    Write-Host "  非微软计划任务 (活跃): $enabledTasks 个"

    Write-Host "`n使用参数可以验证具体变更是否生效。运行 Get-Help .\verify.ps1 查看用法。" -ForegroundColor DarkGray
    return
}

# ── 汇总 ──
Write-Host "`n$('=' * 40)" -ForegroundColor Cyan
$color = if ($failCount -eq 0) { 'Green' } else { 'Red' }
Write-Host "验证完成: PASS $passCount | FAIL $failCount" -ForegroundColor $color
