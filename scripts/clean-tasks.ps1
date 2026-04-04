#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep 计划任务清理 — 列出或禁用不必要的计划任务。
.DESCRIPTION
    识别并禁用非微软的遥测、更新检查等不必要的计划任务。
    特别关注绕过服务禁用的任务（如 Intel esrv.exe）。
.PARAMETER Action
    操作模式: List（列出可清理任务）或 Disable（禁用指定任务）。
.PARAMETER TaskNames
    要禁用的任务名称数组。Action 为 Disable 时必填。
    支持通配符匹配。
.PARAMETER IncludeMicrosoft
    List 模式下是否包含微软任务（默认排除）。
.NOTES
    需要管理员权限来禁用系统级计划任务。
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('List', 'Disable')]
    [string]$Action = 'List',

    [string[]]$TaskNames,

    [switch]$IncludeMicrosoft
)

# 已知遥测/无用任务关键词模式
$telemetryPattern = 'telemetry|CEIP|SQM|DiagTrack|ESRV|IntelSURQC|NvTm|AdobeGC|UsageReport|Compatibility ?Appraiser|ProgramDataUpdater|Consolidator|UsbCeip|DiskDiagnosticDataCollector'

switch ($Action) {
    'List' {
        Write-Host "扫描计划任务..." -ForegroundColor Cyan

        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -ne 'Disabled' -and
                ($IncludeMicrosoft -or $_.TaskPath -notmatch '^\\Microsoft\\')
            }

        # 分类
        $telemetryTasks = @()
        $obsoleteTasks = @()
        $otherTasks = @()

        foreach ($t in $tasks) {
            $actionStr = ($t.Actions | ForEach-Object {
                if ($_.Execute) { $_.Execute + ' ' + $_.Arguments }
            }) -join '; '

            $obj = [PSCustomObject]@{
                TaskName   = $t.TaskName
                TaskPath   = $t.TaskPath
                State      = $t.State
                Actions    = if ($actionStr.Length -gt 80) { $actionStr.Substring(0, 77) + '...' } else { $actionStr }
                Category   = ''
            }

            # 判断类别
            if ($t.TaskName -match $telemetryPattern -or $actionStr -match $telemetryPattern) {
                $obj.Category = 'Telemetry'
                $telemetryTasks += $obj
            } elseif ($actionStr -and $actionStr -notmatch '^\s*$') {
                # 检查可执行文件是否存在
                $exe = ($t.Actions | Select-Object -First 1).Execute
                if ($exe -and $exe -notmatch '^%' -and -not (Test-Path $exe -ErrorAction SilentlyContinue)) {
                    $obj.Category = 'Obsolete'
                    $obsoleteTasks += $obj
                } else {
                    $obj.Category = 'Other'
                    $otherTasks += $obj
                }
            } else {
                $obj.Category = 'Other'
                $otherTasks += $obj
            }
        }

        # 输出
        if ($telemetryTasks.Count -gt 0) {
            Write-Host "`n=== 遥测任务 ($($telemetryTasks.Count) 个) — 建议禁用 ===" -ForegroundColor Red
            $telemetryTasks | Select-Object TaskName, TaskPath, Actions |
                Format-Table -AutoSize -Wrap
        }

        if ($obsoleteTasks.Count -gt 0) {
            Write-Host "=== 残留任务 (exe 不存在, $($obsoleteTasks.Count) 个) — 建议禁用 ===" -ForegroundColor Yellow
            $obsoleteTasks | Select-Object TaskName, TaskPath, Actions |
                Format-Table -AutoSize -Wrap
        }

        if ($otherTasks.Count -gt 0) {
            Write-Host "=== 其他非微软任务 ($($otherTasks.Count) 个) — 需逐个判断 ===" -ForegroundColor Cyan
            $otherTasks | Select-Object TaskName, TaskPath, State, Actions |
                Format-Table -AutoSize -Wrap
        }

        $total = $telemetryTasks.Count + $obsoleteTasks.Count + $otherTasks.Count
        Write-Host "共 $total 个活跃的非微软计划任务。" -ForegroundColor Cyan
    }

    'Disable' {
        if (-not $TaskNames -or $TaskNames.Count -eq 0) {
            Write-Error "Disable 操作需要指定 -TaskNames 参数。"
            exit 1
        }

        foreach ($pattern in $TaskNames) {
            $matched = Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -like $pattern -and $_.State -ne 'Disabled' }

            if (-not $matched -or $matched.Count -eq 0) {
                Write-Host "  [SKIP] '$pattern' — 未匹配到活跃任务" -ForegroundColor DarkYellow
                continue
            }

            foreach ($t in $matched) {
                Write-Host "  [DISABLE] $($t.TaskPath)$($t.TaskName)" -ForegroundColor White -NoNewline
                try {
                    $t | Disable-ScheduledTask -ErrorAction Stop | Out-Null
                    Write-Host " ✓" -ForegroundColor Green
                } catch {
                    Write-Host " ✗" -ForegroundColor Red
                    Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        Write-Host "`n恢复: Enable-ScheduledTask -TaskName 'TaskName'" -ForegroundColor Cyan
    }
}
