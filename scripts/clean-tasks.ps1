#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep scheduled task cleanup — list or disable unnecessary scheduled tasks.
.DESCRIPTION
    Identifies and disables non-Microsoft telemetry, update-checking, and other
    unnecessary scheduled tasks. Specifically targets tasks that bypass service
    disabling (e.g., Intel esrv.exe).
.PARAMETER Action
    Operation mode: List (list cleanable tasks) or Disable (disable specified tasks).
.PARAMETER TaskNames
    Array of task names to disable. Required when Action is Disable.
    Supports wildcard matching.
.PARAMETER IncludeMicrosoft
    Whether to include Microsoft tasks in List mode (excluded by default).
.NOTES
    Requires admin privileges to disable system-level scheduled tasks.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('List', 'Disable')]
    [string]$Action = 'List',

    [string[]]$TaskNames,

    [switch]$IncludeMicrosoft
)

# Known telemetry/unnecessary task keyword patterns
$telemetryPattern = 'telemetry|CEIP|SQM|DiagTrack|ESRV|IntelSURQC|NvTm|AdobeGC|UsageReport|Compatibility ?Appraiser|ProgramDataUpdater|Consolidator|UsbCeip|DiskDiagnosticDataCollector'

switch ($Action) {
    'List' {
        Write-Host "Scanning scheduled tasks..." -ForegroundColor Cyan

        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -ne 'Disabled' -and
                ($IncludeMicrosoft -or $_.TaskPath -notmatch '^\\Microsoft\\')
            }

        # Categorize
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

            # Determine category
            if ($t.TaskName -match $telemetryPattern -or $actionStr -match $telemetryPattern) {
                $obj.Category = 'Telemetry'
                $telemetryTasks += $obj
            } elseif ($actionStr -and $actionStr -notmatch '^\s*$') {
                # Check if executable file exists
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

        # Output
        if ($telemetryTasks.Count -gt 0) {
            Write-Host "`n=== Telemetry Tasks ($($telemetryTasks.Count)) — recommended to disable ===" -ForegroundColor Red
            $telemetryTasks | Select-Object TaskName, TaskPath, Actions |
                Format-Table -AutoSize -Wrap
        }

        if ($obsoleteTasks.Count -gt 0) {
            Write-Host "=== Obsolete Tasks (exe missing, $($obsoleteTasks.Count)) — recommended to disable ===" -ForegroundColor Yellow
            $obsoleteTasks | Select-Object TaskName, TaskPath, Actions |
                Format-Table -AutoSize -Wrap
        }

        if ($otherTasks.Count -gt 0) {
            Write-Host "=== Other Non-Microsoft Tasks ($($otherTasks.Count)) — review individually ===" -ForegroundColor Cyan
            $otherTasks | Select-Object TaskName, TaskPath, State, Actions |
                Format-Table -AutoSize -Wrap
        }

        $total = $telemetryTasks.Count + $obsoleteTasks.Count + $otherTasks.Count
        Write-Host "Total: $total active non-Microsoft scheduled tasks." -ForegroundColor Cyan
    }

    'Disable' {
        if (-not $TaskNames -or $TaskNames.Count -eq 0) {
            Write-Error "Disable action requires the -TaskNames parameter."
            exit 1
        }

        foreach ($pattern in $TaskNames) {
            $matched = Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -like $pattern -and $_.State -ne 'Disabled' }

            if (-not $matched -or $matched.Count -eq 0) {
                Write-Host "  [SKIP] '$pattern' — no matching active tasks" -ForegroundColor DarkYellow
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

        Write-Host "`nRestore: Enable-ScheduledTask -TaskName 'TaskName'" -ForegroundColor Cyan
    }
}
