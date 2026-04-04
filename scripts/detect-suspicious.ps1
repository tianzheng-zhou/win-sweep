#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win-sweep suspicious service detection — find leftover/unsigned services.
.DESCRIPTION
    Scans all registered services and calculates a quantified risk score based on
    12 risk signals, identifying suspicious indicators: missing executables, no digital
    signature, high-privilege accounts, failure auto-restart, garbled service names, etc.
.PARAMETER MinScore
    Minimum risk score to display (default 2, filters out low-score noise).
.PARAMETER IncludeMicrosoft
    Whether to include services with paths in System32 signed by Microsoft (excluded by default).
#>

[CmdletBinding()]
param(
    [int]$MinScore = 2,
    [switch]$IncludeMicrosoft
)

function Get-ExePathFromImagePath([string]$ImagePath) {
    # Extract actual executable path from ImagePath (strip arguments and quotes)
    $p = $ImagePath.Trim()
    if ($p.StartsWith('"')) {
        $end = $p.IndexOf('"', 1)
        if ($end -gt 0) { return $p.Substring(1, $end - 1) }
    }
    # No quotes: try segment-matching for .exe
    if ($p -match '^(.+\.exe)\b') { return $Matches[1] }
    # svchost etc.
    if ($p -match '^(\S+)') { return $Matches[1] }
    return $p
}

Write-Host "Scanning all services, calculating risk scores..." -ForegroundColor Cyan

$allServices = Get-CimInstance Win32_Service
$results = @()

foreach ($svc in $allServices) {
    $score = 0
    $signals = @()

    # ── Extract executable path ──
    $exePath = $null
    $fileExists = $false
    if ($svc.PathName) {
        $exePath = Get-ExePathFromImagePath $svc.PathName
        # Expand environment variables
        $exePathExpanded = [Environment]::ExpandEnvironmentVariables($exePath)
        $fileExists = Test-Path $exePathExpanded -ErrorAction SilentlyContinue
    }

    # ── S1: Executable file not found (+3) ──
    if ($svc.PathName -and -not $fileExists) {
        $score += 3; $signals += 'S1:FileNotFound'
    }

    # ── Skip Microsoft svchost services (unless explicitly requested) ──
    if (-not $IncludeMicrosoft -and $svc.PathName -match 'windows\\system32' -and $fileExists) {
        # Quick skip for obvious system services to reduce signature check overhead
        if ($svc.PathName -match 'svchost\.exe') { continue }
    }

    # ── S2/S3: Signature check ──
    $sigStatus = $null
    if ($fileExists -and $exePathExpanded) {
        try {
            $sig = Get-AuthenticodeSignature $exePathExpanded -ErrorAction Stop
            $sigStatus = $sig.Status
            if ($sig.Status -eq 'NotSigned') {
                $score += 3; $signals += 'S2:NotSigned'
            } elseif ($sig.Status -ne 'Valid') {
                $score += 4; $signals += "S3:BadSig($($sig.Status))"
            }
            # Exclude legitimately signed Microsoft services
            if (-not $IncludeMicrosoft -and $sig.Status -eq 'Valid' -and
                $sig.SignerCertificate.Subject -match 'Microsoft') {
                if ($score -eq 0) { continue }
            }
        } catch {
            # Unable to check signature
        }
    }

    # ── S4: LocalSystem (+2) ──
    if ($svc.StartName -eq 'LocalSystem') {
        $score += 2; $signals += 'S4:LocalSystem'
    }

    # ── S5: Failure auto-restart (+1) ──
    $failRestart = $false
    try {
        $failOut = sc.exe qfailure $svc.Name 2>$null | Out-String
        if ($failOut -match 'RESTART') {
            $score += 1; $signals += 'S5:FailRestart'
            $failRestart = $true
        }
    } catch {}

    # ── S6: Path in user-writable directory (+3) ──
    if ($exePath -and $exePath -match '(ProgramData|\\Temp\\|AppData|Downloads)') {
        $score += 3; $signals += 'S6:WritablePath'
    }

    # ── S7: Garbled service/display name (+4) ──
    $namePattern = '[^\x20-\x7E\u4E00-\u9FFF\u3000-\u303F]'  # Non-ASCII printable + non-CJK
    if ($svc.Name -match '^[a-zA-Z0-9]{16,}$' -or  # Random long string
        $svc.Name -match $namePattern -or
        ($svc.DisplayName -and $svc.DisplayName -match $namePattern)) {
        $score += 4; $signals += 'S7:SuspiciousName'
    }

    # ── S8: Empty description (+1) ──
    if (-not $svc.Description -or $svc.Description.Trim() -eq '') {
        $score += 1; $signals += 'S8:NoDescription'
    }

    # ── S9: Suspicious arguments in ImagePath (+5) ──
    if ($svc.PathName -match '(-encode|-hidden|bypass|downloadstring|webclient|invoke-expression)') {
        $score += 5; $signals += 'S9:SuspiciousArgs'
    }

    # ── S11: No DisplayName (+2) ──
    if (-not $svc.DisplayName -or $svc.DisplayName.Trim() -eq '') {
        $score += 2; $signals += 'S11:NoDisplayName'
    }

    # ── S12: svchost DLL service pointing to non-existent DLL (+4) ──
    if ($svc.PathName -match 'svchost\.exe' -and $svc.Name) {
        try {
            $dllPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)\Parameters" -Name ServiceDll -ErrorAction Stop).ServiceDll
            $dllExpanded = [Environment]::ExpandEnvironmentVariables($dllPath)
            if (-not (Test-Path $dllExpanded)) {
                $score += 4; $signals += 'S12:MissingDLL'
            }
        } catch {
            # No Parameters\ServiceDll — normal (not a DLL service)
        }
    }

    # ── Filter low scores ──
    if ($score -ge $MinScore) {
        $results += [PSCustomObject]@{
            Score       = $score
            RiskLevel   = if ($score -ge 7) {'HIGH'} elseif ($score -ge 4) {'MED'} else {'LOW'}
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            State       = $svc.State
            StartMode   = $svc.StartMode
            Account     = $svc.StartName
            Signals     = ($signals -join ', ')
            ExePath     = $exePath
            FileExists  = $fileExists
        }
    }
}

# ── Output ──
$results = $results | Sort-Object Score -Descending

$high = ($results | Where-Object RiskLevel -eq 'HIGH').Count
$med  = ($results | Where-Object RiskLevel -eq 'MED').Count
$low  = ($results | Where-Object RiskLevel -eq 'LOW').Count

Write-Host "`nScan complete: $($allServices.Count) services scanned, $($results.Count) flagged as suspicious" -ForegroundColor Cyan
Write-Host "  HIGH: $high | MED: $med | LOW: $low" -ForegroundColor $(if ($high -gt 0) {'Red'} else {'Green'})

if ($results.Count -gt 0) {
    Write-Host "`n=== HIGH Risk (7+) ===" -ForegroundColor Red
    $results | Where-Object RiskLevel -eq 'HIGH' |
        Select-Object Score, Name, DisplayName, Account, Signals, ExePath, FileExists |
        Format-Table -AutoSize -Wrap

    Write-Host "=== MED Risk (4-6) ===" -ForegroundColor Yellow
    $results | Where-Object RiskLevel -eq 'MED' |
        Select-Object Score, Name, DisplayName, Account, Signals, ExePath |
        Format-Table -AutoSize -Wrap

    Write-Host "=== LOW Risk (2-3) ===" -ForegroundColor DarkYellow
    $results | Where-Object RiskLevel -eq 'LOW' |
        Select-Object Score, Name, DisplayName, Signals |
        Format-Table -AutoSize -Wrap
} else {
    Write-Host "`nNo suspicious services found." -ForegroundColor Green
}
