#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WinSweep 可疑服务检测 — 查找残留/未签名的服务。
.DESCRIPTION
    扫描所有已注册服务，查找可疑迹象：可执行文件丢失、
    无数字签名、高权限账户 + 失败自动重启、乱码服务名等。
#>

[CmdletBinding()]
param()

# TODO: 实现可疑服务检测
# - 枚举所有服务
# - 检查 PathName 可执行文件是否存在
# - 检查数字签名（Get-AuthenticodeSignature）
# - 标记以 LocalSystem 运行且配置自动重启的服务
# - 标记显示名含乱码或非 ASCII 字符的服务
# - 输出发现报告（含风险等级）
