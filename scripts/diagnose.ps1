#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep 系统诊断 — 扫描并报告系统状态。
.DESCRIPTION
    收集磁盘用量、已安装软件、启动项、服务、
    计划任务、内存占用排行等信息，输出结构化报告。
.NOTES
    完整结果需要管理员权限的 PowerShell。
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$PSScriptRoot\..\reports"
)

# TODO: 实现诊断数据收集
# - 系统信息
# - 磁盘用量（分卷 + 顶层目录大小）
# - 已安装软件（按大小排序，从注册表读取）
# - HKCU 和 HKLM 的 Run 启动项
# - 自动启动服务（突出非微软服务）
# - 非微软的已启用计划任务
# - 前 30 个非系统进程的内存占用
