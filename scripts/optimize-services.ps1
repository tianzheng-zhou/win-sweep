#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win-sweep 服务优化 — 批量修改服务启动模式。
.DESCRIPTION
    根据 AI 传入的服务列表修改启动模式（Auto → Manual/Disabled）。
    修改前自动导出当前配置作为备份。
    脚本本身不做决策——由 AI 根据 service-rules.md 框架判断后指定操作。
.PARAMETER Services
    JSON 格式的服务操作列表。
    示例: '[{"Name":"FlexNet","Target":"Manual"},{"Name":"DiagTrack","Target":"Disabled"}]'
.PARAMETER BackupDir
    备份目录，默认为 %TEMP%\win-sweep-backup。
.PARAMETER DryRun
    仅预览，不实际修改。
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Services,

    [string]$BackupDir = "$env:TEMP\win-sweep-backup",

    [switch]$DryRun
)

# ── 解析输入 ──
try {
    $serviceList = $Services | ConvertFrom-Json
} catch {
    Write-Error "无法解析 Services 参数。请提供有效的 JSON 数组。"
    Write-Error "格式: '[{`"Name`":`"ServiceName`",`"Target`":`"Manual`"}]'"
    exit 1
}

if ($serviceList.Count -eq 0) {
    Write-Host "无服务需要修改。" -ForegroundColor Yellow
    exit 0
}

# ── 验证目标值 ──
$validTargets = @('Manual', 'Disabled', 'Auto')
$targetMap = @{ 'Manual' = 'demand'; 'Disabled' = 'disabled'; 'Auto' = 'auto' }

foreach ($item in $serviceList) {
    if ($item.Target -notin $validTargets) {
        Write-Error "无效的 Target '$($item.Target)' (服务: $($item.Name))。有效值: $($validTargets -join ', ')"
        exit 1
    }
}

# ── 备份 ──
if (-not (Test-Path $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path $BackupDir "services-backup-$timestamp.csv"

Write-Host "备份当前服务配置..." -ForegroundColor Cyan
$currentAll = Get-CimInstance Win32_Service |
    Select-Object Name, DisplayName, StartMode, State, StartName, PathName
$currentAll | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
Write-Host "  已备份到: $backupFile" -ForegroundColor Green

# ── 逐个修改 ──
$succeeded = @()
$failed = @()
$skipped = @()

foreach ($item in $serviceList) {
    $svcName = $item.Name
    $target = $item.Target
    $scTarget = $targetMap[$target]

    # 检查服务是否存在
    $current = $currentAll | Where-Object { $_.Name -eq $svcName }
    if (-not $current) {
        Write-Host "  [SKIP] $svcName — 服务不存在" -ForegroundColor DarkYellow
        $skipped += [PSCustomObject]@{ Name=$svcName; Reason='NotFound' }
        continue
    }

    # 检查是否已是目标模式
    $currentMode = $current.StartMode
    if (($currentMode -eq 'Manual' -and $target -eq 'Manual') -or
        ($currentMode -eq 'Disabled' -and $target -eq 'Disabled') -or
        ($currentMode -eq 'Auto' -and $target -eq 'Auto')) {
        Write-Host "  [SKIP] $svcName — 已经是 $target" -ForegroundColor DarkGray
        $skipped += [PSCustomObject]@{ Name=$svcName; Reason="Already $target" }
        continue
    }

    if ($DryRun) {
        Write-Host "  [DRY ] $svcName : $currentMode → $target" -ForegroundColor Magenta
        $succeeded += [PSCustomObject]@{ Name=$svcName; From=$currentMode; To=$target; Status='DryRun' }
        continue
    }

    # 执行修改（用单引号包裹服务名，防止 $ 被展开）
    Write-Host "  [EXEC] $svcName : $currentMode → $target" -ForegroundColor White -NoNewline
    $output = sc.exe config "$svcName" start= $scTarget 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $output -match 'SUCCESS') {
        Write-Host " ✓" -ForegroundColor Green
        $succeeded += [PSCustomObject]@{
            Name=$svcName; From=$currentMode; To=$target; Status='OK'
            Timestamp=(Get-Date -Format 'HH:mm:ss')
            Command="sc.exe config `"$svcName`" start= $scTarget"
        }
    } else {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host "    $($output.Trim())" -ForegroundColor Red
        $failed += [PSCustomObject]@{ Name=$svcName; From=$currentMode; To=$target; Error=$output.Trim() }
    }
}

# ── 汇总 ──
Write-Host "`n$('=' * 50)" -ForegroundColor Cyan
Write-Host "汇总: 成功 $($succeeded.Count) | 失败 $($failed.Count) | 跳过 $($skipped.Count)" -ForegroundColor Cyan

if ($succeeded.Count -gt 0) {
    Write-Host "`n成功:" -ForegroundColor Green
    $succeeded | Format-Table -AutoSize
}
if ($failed.Count -gt 0) {
    Write-Host "`n失败:" -ForegroundColor Red
    $failed | Format-Table -AutoSize
}

Write-Host "`n备份位置: $backupFile" -ForegroundColor Cyan
Write-Host "回滚: 手动参考备份 CSV 中的 StartMode 列，使用 sc.exe config 恢复。" -ForegroundColor Cyan
