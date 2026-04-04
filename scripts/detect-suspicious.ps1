#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win-sweep 可疑服务检测 — 查找残留/未签名的服务。
.DESCRIPTION
    扫描所有已注册服务，基于 12 个风险信号计算量化评分，
    识别可疑迹象：可执行文件丢失、无数字签名、高权限账户、
    失败自动重启、乱码服务名等。
.PARAMETER MinScore
    最低显示风险分（默认 2，过滤低分噪音）。
.PARAMETER IncludeMicrosoft
    是否包含路径在 System32 且签名为 Microsoft 的服务（默认排除）。
#>

[CmdletBinding()]
param(
    [int]$MinScore = 2,
    [switch]$IncludeMicrosoft
)

function Get-ExePathFromImagePath([string]$ImagePath) {
    # 从 ImagePath 提取实际可执行文件路径（去掉参数和引号）
    $p = $ImagePath.Trim()
    if ($p.StartsWith('"')) {
        $end = $p.IndexOf('"', 1)
        if ($end -gt 0) { return $p.Substring(1, $end - 1) }
    }
    # 无引号：尝试逐段匹配 .exe
    if ($p -match '^(.+\.exe)\b') { return $Matches[1] }
    # svchost 等
    if ($p -match '^(\S+)') { return $Matches[1] }
    return $p
}

Write-Host "扫描所有服务，计算风险评分..." -ForegroundColor Cyan

$allServices = Get-CimInstance Win32_Service
$results = @()

foreach ($svc in $allServices) {
    $score = 0
    $signals = @()

    # ── 提取可执行路径 ──
    $exePath = $null
    $fileExists = $false
    if ($svc.PathName) {
        $exePath = Get-ExePathFromImagePath $svc.PathName
        # 展开环境变量
        $exePathExpanded = [Environment]::ExpandEnvironmentVariables($exePath)
        $fileExists = Test-Path $exePathExpanded -ErrorAction SilentlyContinue
    }

    # ── S1: 可执行文件不存在 (+3) ──
    if ($svc.PathName -and -not $fileExists) {
        $score += 3; $signals += 'S1:FileNotFound'
    }

    # ── 跳过 Microsoft svchost 服务（除非明确要求） ──
    if (-not $IncludeMicrosoft -and $svc.PathName -match 'windows\\system32' -and $fileExists) {
        # 快速跳过明显的系统服务，减少签名检查开销
        if ($svc.PathName -match 'svchost\.exe') { continue }
    }

    # ── S2/S3: 签名检查 ──
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
            # 排除 Microsoft 签名的合法服务
            if (-not $IncludeMicrosoft -and $sig.Status -eq 'Valid' -and
                $sig.SignerCertificate.Subject -match 'Microsoft') {
                if ($score -eq 0) { continue }
            }
        } catch {
            # 无法检查签名
        }
    }

    # ── S4: LocalSystem (+2) ──
    if ($svc.StartName -eq 'LocalSystem') {
        $score += 2; $signals += 'S4:LocalSystem'
    }

    # ── S5: 失败自动重启 (+1) ──
    $failRestart = $false
    try {
        $failOut = sc.exe qfailure $svc.Name 2>$null | Out-String
        if ($failOut -match 'RESTART') {
            $score += 1; $signals += 'S5:FailRestart'
            $failRestart = $true
        }
    } catch {}

    # ── S6: 路径在用户可写目录 (+3) ──
    if ($exePath -and $exePath -match '(ProgramData|\\Temp\\|AppData|Downloads)') {
        $score += 3; $signals += 'S6:WritablePath'
    }

    # ── S7: 服务名/显示名乱码 (+4) ──
    $namePattern = '[^\x20-\x7E\u4E00-\u9FFF\u3000-\u303F]'  # 非 ASCII 可打印 + 非中文
    if ($svc.Name -match '^[a-zA-Z0-9]{16,}$' -or  # 随机长字符串
        $svc.Name -match $namePattern -or
        ($svc.DisplayName -and $svc.DisplayName -match $namePattern)) {
        $score += 4; $signals += 'S7:SuspiciousName'
    }

    # ── S8: 描述为空 (+1) ──
    if (-not $svc.Description -or $svc.Description.Trim() -eq '') {
        $score += 1; $signals += 'S8:NoDescription'
    }

    # ── S9: ImagePath 含可疑参数 (+5) ──
    if ($svc.PathName -match '(-encode|-hidden|bypass|downloadstring|webclient|invoke-expression)') {
        $score += 5; $signals += 'S9:SuspiciousArgs'
    }

    # ── S11: 无 DisplayName (+2) ──
    if (-not $svc.DisplayName -or $svc.DisplayName.Trim() -eq '') {
        $score += 2; $signals += 'S11:NoDisplayName'
    }

    # ── S12: svchost DLL 服务指向不存在的 DLL (+4) ──
    if ($svc.PathName -match 'svchost\.exe' -and $svc.Name) {
        try {
            $dllPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)\Parameters" -Name ServiceDll -ErrorAction Stop).ServiceDll
            $dllExpanded = [Environment]::ExpandEnvironmentVariables($dllPath)
            if (-not (Test-Path $dllExpanded)) {
                $score += 4; $signals += 'S12:MissingDLL'
            }
        } catch {
            # 无 Parameters\ServiceDll — 正常（非 DLL 服务）
        }
    }

    # ── 过滤低分 ──
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

# ── 输出 ──
$results = $results | Sort-Object Score -Descending

$high = ($results | Where-Object RiskLevel -eq 'HIGH').Count
$med  = ($results | Where-Object RiskLevel -eq 'MED').Count
$low  = ($results | Where-Object RiskLevel -eq 'LOW').Count

Write-Host "`n扫描完成: $($allServices.Count) 个服务, 标记 $($results.Count) 个可疑" -ForegroundColor Cyan
Write-Host "  HIGH: $high | MED: $med | LOW: $low" -ForegroundColor $(if ($high -gt 0) {'Red'} else {'Green'})

if ($results.Count -gt 0) {
    Write-Host "`n=== HIGH 风险 (7+) ===" -ForegroundColor Red
    $results | Where-Object RiskLevel -eq 'HIGH' |
        Select-Object Score, Name, DisplayName, Account, Signals, ExePath, FileExists |
        Format-Table -AutoSize -Wrap

    Write-Host "=== MED 风险 (4-6) ===" -ForegroundColor Yellow
    $results | Where-Object RiskLevel -eq 'MED' |
        Select-Object Score, Name, DisplayName, Account, Signals, ExePath |
        Format-Table -AutoSize -Wrap

    Write-Host "=== LOW 风险 (2-3) ===" -ForegroundColor DarkYellow
    $results | Where-Object RiskLevel -eq 'LOW' |
        Select-Object Score, Name, DisplayName, Signals |
        Format-Table -AutoSize -Wrap
} else {
    Write-Host "`n未发现可疑服务。" -ForegroundColor Green
}
