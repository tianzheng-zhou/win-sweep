#Requires -Version 5.1
<#
.SYNOPSIS
    WinSweep 启动项管理 — 禁用启动项并安全备份。
.DESCRIPTION
    将选定的 HKCU\Run 条目移动到 HKCU\RunDisabled，
    实现安全禁用。支持恢复单个启动项。
.NOTES
    HKCU 条目不需要管理员权限。
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun,
    [switch]$Restore
)

# TODO: 实现启动项管理
# - 列出当前 HKCU\Run 和 HKLM\Run 条目
# - 将选定条目移动到 RunDisabled（备份）
# - 恢复模式：从 RunDisabled 移回
# - 报告变更
