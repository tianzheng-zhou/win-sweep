#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep 启动项管理 — 禁用启动项并安全备份。
.DESCRIPTION
    将选定的 Run 条目移动到 RunDisabled 键，实现安全禁用。
    支持恢复单个启动项。HKCU 条目不需要管理员权限。
.PARAMETER Action
    操作模式: List（列出）, Disable（禁用）, Restore（恢复）。
.PARAMETER Names
    要禁用/恢复的启动项名称数组。Action 为 Disable 或 Restore 时必填。
.PARAMETER Scope
    注册表范围: HKCU（默认）或 HKLM（需管理员权限）。
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

# 排除注册表默认属性
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
        Write-Host "`n$Scope\Run (活跃启动项):" -ForegroundColor Cyan
        $active = Get-RunEntries $runPath
        if ($active.Count -gt 0) {
            $active | Format-Table -AutoSize -Wrap
        } else {
            Write-Host "  (empty)" -ForegroundColor DarkGray
        }

        Write-Host "`n$Scope\RunDisabled (已禁用备份):" -ForegroundColor Cyan
        $disabled = Get-RunEntries $disabledPath
        if ($disabled.Count -gt 0) {
            $disabled | Format-Table -AutoSize -Wrap
        } else {
            Write-Host "  (empty)" -ForegroundColor DarkGray
        }
    }

    'Disable' {
        if (-not $Names -or $Names.Count -eq 0) {
            Write-Error "Disable 操作需要指定 -Names 参数。"
            exit 1
        }

        # 确保 RunDisabled 键存在
        if (-not (Test-Path $disabledPath)) {
            New-Item -Path $disabledPath -Force | Out-Null
        }

        foreach ($name in $Names) {
            # 检查启动项是否存在
            $value = $null
            try {
                $value = (Get-ItemProperty $runPath -Name $name -ErrorAction Stop).$name
            } catch {
                Write-Host "  [SKIP] '$name' — 在 $Scope\Run 中不存在" -ForegroundColor DarkYellow
                continue
            }

            # 移动到 RunDisabled
            Write-Host "  [MOVE] '$name' → RunDisabled" -ForegroundColor White -NoNewline
            try {
                Set-ItemProperty -Path $disabledPath -Name $name -Value $value
                Remove-ItemProperty -Path $runPath -Name $name
                Write-Host " ✓" -ForegroundColor Green
                Write-Host "    命令: $value" -ForegroundColor DarkGray
            } catch {
                Write-Host " ✗" -ForegroundColor Red
                Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        Write-Host "`n恢复命令: .\manage-startups.ps1 -Action Restore -Names 'ItemName' -Scope $Scope" -ForegroundColor Cyan
    }

    'Restore' {
        if (-not $Names -or $Names.Count -eq 0) {
            Write-Error "Restore 操作需要指定 -Names 参数。"
            exit 1
        }

        foreach ($name in $Names) {
            $value = $null
            try {
                $value = (Get-ItemProperty $disabledPath -Name $name -ErrorAction Stop).$name
            } catch {
                Write-Host "  [SKIP] '$name' — 在 RunDisabled 中不存在" -ForegroundColor DarkYellow
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
