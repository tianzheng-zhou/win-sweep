#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win-sweep service optimization — batch-modify service startup modes.
.DESCRIPTION
    Modifies service startup modes (Auto → Manual/Disabled) based on the service list
    provided by the AI. Automatically exports current configuration as a backup before changes.
    This script does not make decisions — the AI determines actions based on the
    service-rules.md framework and specifies them here.
.PARAMETER Services
    JSON-formatted service operation list.
    Example: '[{"Name":"FlexNet","Target":"Manual"},{"Name":"DiagTrack","Target":"Disabled"}]'
.PARAMETER BackupDir
    Backup directory, defaults to %TEMP%\win-sweep-backup.
.PARAMETER DryRun
    Preview only, no actual modifications.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Services,

    [string]$BackupDir = "$env:TEMP\win-sweep-backup",

    [switch]$DryRun
)

# ── Parse input ──
try {
    $serviceList = $Services | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse Services parameter. Please provide a valid JSON array."
    Write-Error "Format: '[{`"Name`":`"ServiceName`",`"Target`":`"Manual`"}]'"
    exit 1
}

if ($serviceList.Count -eq 0) {
    Write-Host "No services to modify." -ForegroundColor Yellow
    exit 0
}

# ── Validate target values ──
$validTargets = @('Manual', 'Disabled', 'Auto')
$targetMap = @{ 'Manual' = 'demand'; 'Disabled' = 'disabled'; 'Auto' = 'auto' }

foreach ($item in $serviceList) {
    if ($item.Target -notin $validTargets) {
        Write-Error "Invalid Target '$($item.Target)' (service: $($item.Name)). Valid values: $($validTargets -join ', ')"
        exit 1
    }
}

# ── Backup ──
if (-not (Test-Path $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path $BackupDir "services-backup-$timestamp.csv"

Write-Host "Backing up current service configuration..." -ForegroundColor Cyan
$currentAll = Get-CimInstance Win32_Service |
    Select-Object Name, DisplayName, StartMode, State, StartName, PathName
$currentAll | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
Write-Host "  Backed up to: $backupFile" -ForegroundColor Green

# ── Modify one by one ──
$succeeded = @()
$failed = @()
$skipped = @()

foreach ($item in $serviceList) {
    $svcName = $item.Name
    $target = $item.Target
    $scTarget = $targetMap[$target]

    # Check if service exists
    $current = $currentAll | Where-Object { $_.Name -eq $svcName }
    if (-not $current) {
        Write-Host "  [SKIP] $svcName — service not found" -ForegroundColor DarkYellow
        $skipped += [PSCustomObject]@{ Name=$svcName; Reason='NotFound' }
        continue
    }

    # Check if already at target mode
    $currentMode = $current.StartMode
    if (($currentMode -eq 'Manual' -and $target -eq 'Manual') -or
        ($currentMode -eq 'Disabled' -and $target -eq 'Disabled') -or
        ($currentMode -eq 'Auto' -and $target -eq 'Auto')) {
        Write-Host "  [SKIP] $svcName — already $target" -ForegroundColor DarkGray
        $skipped += [PSCustomObject]@{ Name=$svcName; Reason="Already $target" }
        continue
    }

    if ($DryRun) {
        Write-Host "  [DRY ] $svcName : $currentMode → $target" -ForegroundColor Magenta
        $succeeded += [PSCustomObject]@{ Name=$svcName; From=$currentMode; To=$target; Status='DryRun' }
        continue
    }

    # Execute change (quote service name to prevent $ expansion)
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

# ── Summary ──
Write-Host "`n$('=' * 50)" -ForegroundColor Cyan
Write-Host "Summary: Succeeded $($succeeded.Count) | Failed $($failed.Count) | Skipped $($skipped.Count)" -ForegroundColor Cyan

if ($succeeded.Count -gt 0) {
    Write-Host "`nSucceeded:" -ForegroundColor Green
    $succeeded | Format-Table -AutoSize
}
if ($failed.Count -gt 0) {
    Write-Host "`nFailed:" -ForegroundColor Red
    $failed | Format-Table -AutoSize
}

Write-Host "`nBackup location: $backupFile" -ForegroundColor Cyan
Write-Host "Rollback: Refer to the StartMode column in the backup CSV and use sc.exe config to restore." -ForegroundColor Cyan
