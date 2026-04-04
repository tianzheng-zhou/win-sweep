# sc.exe 和 PowerShell 常见坑

用 PowerShell 管理 Windows 服务时的常见陷阱。

## sc.exe 语法：等号后必须有空格

`sc.exe config` 要求等号后面有一个空格。这是 sc.exe 自己的语法，不是 PowerShell 的问题。

```powershell
# 正确
sc.exe config "ServiceName" start= demand

# 错误 — 会静默失败或报错
sc.exe config "ServiceName" start=demand
```

## 服务名包含 `$` 的问题

SQL Server 命名实例使用 `MSSQL$实例名` 格式。PowerShell 会把 `$` 解释为变量。

```powershell
# 正确 — 单引号阻止变量展开
sc.exe config 'MSSQL$TEW_SQLEXPRESS' start= demand

# 正确 — 反引号转义 $
sc.exe config "MSSQL`$TEW_SQLEXPRESS" start= demand

# 错误 — $TEW_SQLEXPRESS 被当作变量（解析为空）
sc.exe config "MSSQL$TEW_SQLEXPRESS" start= demand
```

## sc.exe 与 Set-Service 对比

| 功能 | sc.exe | Set-Service |
|------|--------|-------------|
| 启动模式 | `start= demand` | `-StartupType Manual` |
| 美元符号 | 需要引号包裹 | 同样问题 |
| 删除服务 | `sc.exe delete` | 不支持 |
| 远程机器 | `sc.exe \\server` | `-ComputerName` |

推荐使用 `sc.exe` 保持一致性 — 它支持删除服务，且跨 PowerShell 版本行为可预测。

## 静默失败

`sc.exe config` 可能看起来成功但实际未生效的情况：
- 服务名拼错（不报错，只输出 "[SC] ChangeServiceConfig SUCCESS" 但修改了错误的目标）
- PowerShell 展开了服务名中的 `$`

批量操作后始终要验证：
```powershell
Get-WmiObject Win32_Service -Filter "Name='ServiceName'" | Select-Object Name, StartMode
```
