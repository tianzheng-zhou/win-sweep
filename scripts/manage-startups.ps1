#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep startup management — disable startup items with safe backup.
.DESCRIPTION
    Moves selected Run entries to the RunDisabled key for safe disabling.
    Supports restoring individual startup items. HKCU entries do not require admin privileges.
.PARAMETER Action
    Operation mode: List (list items), Disable (disable items), Restore (restore items).
.PARAMETER Names
    Array of startup item names to disable/restore. Required when Action is Disable or Restore.
.PARAMETER Scope
    Registry scope: HKCU (default) or HKLM (requires admin privileges).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('List', 'Disable', 'Restore')]
    [string]$Action = 'List',

    [string[]]$Names,

    [ValidateSet('HKCU', 'HKLM')]
    [string]$Scope = 'HKCU'
)

$runPath     = "${Scope}:\Software\Microsoft\Windows\CurrentVersion\Run"
$disabledPath = "${Scope}:\Software\Microsoft\Windows\CurrentVersion\RunDisabled"

# Exclude default registry properties
$excludeProps = '^PS(Path|ParentPath|ChildName|Provider|Drive)$'

function Get-RunEntries([string]$RegPath) {
    if (-not (Test-Path $RegPath)) { return @() }
    $props = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
    if (-not $props) { return @() }
    $props.PSObject.Properties |
        Where-Object { $_.Name -notmatch $excludeProps } |
        ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Command = $_.Value } }
}

switch ($Action) {
    'List' {
        Write-Host "`n$Scope\Run (active startup items):" -ForegroundColor Cyan
        $active = Get-RunEntries $runPath
        if ($active.Count -gt 0) {
            $active | Format-Table -AutoSize -Wrap
        } else {
            Write-Host "  (empty)" -ForegroundColor DarkGray
        }

        Write-Host "`n$Scope\RunDisabled (disabled backups):" -ForegroundColor Cyan
        $disabled = Get-RunEntries $disabledPath
        if ($disabled.Count -gt 0) {
            $disabled | Format-Table -AutoSize -Wrap
        } else {
            Write-Host "  (empty)" -ForegroundColor DarkGray
        }
    }

    'Disable' {
        if (-not $Names -or $Names.Count -eq 0) {
            Write-Error "Disable action requires the -Names parameter."
            exit 1
        }

        # Ensure the RunDisabled key exists
        if (-not (Test-Path $disabledPath)) {
            New-Item -Path $disabledPath -Force | Out-Null
        }

        foreach ($name in $Names) {
            # Check if startup item exists
            $value = $null
            try {
                $value = (Get-ItemProperty $runPath -Name $name -ErrorAction Stop).$name
            } catch {
                Write-Host "  [SKIP] '$name' — not found in $Scope\Run" -ForegroundColor DarkYellow
                continue
            }

            # Move to RunDisabled
            Write-Host "  [MOVE] '$name' → RunDisabled" -ForegroundColor White -NoNewline
            try {
                Set-ItemProperty -Path $disabledPath -Name $name -Value $value
                Remove-ItemProperty -Path $runPath -Name $name
                Write-Host " ✓" -ForegroundColor Green
                Write-Host "    Command: $value" -ForegroundColor DarkGray
            } catch {
                Write-Host " ✗" -ForegroundColor Red
                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        Write-Host "`nRestore command: .\manage-startups.ps1 -Action Restore -Names 'ItemName' -Scope $Scope" -ForegroundColor Cyan
    }

    'Restore' {
        if (-not $Names -or $Names.Count -eq 0) {
            Write-Error "Restore action requires the -Names parameter."
            exit 1
        }

        foreach ($name in $Names) {
            $value = $null
            try {
                $value = (Get-ItemProperty $disabledPath -Name $name -ErrorAction Stop).$name
            } catch {
                Write-Host "  [SKIP] '$name' — not found in RunDisabled" -ForegroundColor DarkYellow
                continue
            }

            Write-Host "  [RESTORE] '$name' → Run" -ForegroundColor White -NoNewline
            try {
                Set-ItemProperty -Path $runPath -Name $name -Value $value
                Remove-ItemProperty -Path $disabledPath -Name $name
                Write-Host " ✓" -ForegroundColor Green
            } catch {
                Write-Host " ✗" -ForegroundColor Red
                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
