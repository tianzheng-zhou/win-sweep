# 可疑服务排查清单

如何识别和处理未知或潜在恶意的服务。

## 危险信号

| 指标 | 风险等级 | 示例 |
|------|----------|------|
| 显示名是乱码/非 ASCII | 高 | `` `RUdREA^TR `` |
| 可执行文件路径不存在 | 中 | `C:\ProgramData\client\GameBox.exe`（文件已消失） |
| 以 LocalSystem 运行 | 高 | 最高权限，可做任何事 |
| 配置了失败自动重启 | 中 | 持久化机制 |
| 可执行文件未签名 | 中 | 无数字签名 |
| 路径在 `ProgramData`、`Temp` 或 `AppData` | 高 | 对合法服务来说不寻常 |
| 服务名以 `_` 开头或为随机字符 | 中 | 恶意软件/广告软件的命名模式 |

## 排查步骤

1. **检查 `PathName`** — 指向哪个可执行文件？
   ```powershell
   Get-WmiObject Win32_Service -Filter "Name='ServiceName'" | Select-Object PathName
   ```

2. **检查文件是否存在**
   ```powershell
   Test-Path "C:\path\to\executable.exe"
   ```

3. **检查 `ObjectName`** — 以什么账户运行？
   ```powershell
   Get-WmiObject Win32_Service -Filter "Name='ServiceName'" | Select-Object StartName
   ```

4. **检查数字签名**（文件存在时）
   ```powershell
   Get-AuthenticodeSignature "C:\path\to\executable.exe"
   ```

5. **检查失败重启配置**（注册表）
   ```powershell
   reg query "HKLM\SYSTEM\CurrentControlSet\Services\ServiceName" /v FailureActions
   ```

## 决策矩阵

| 文件存在 | 已签名 | 账户 | 处理方式 |
|----------|--------|------|--------|
| 否 | 不适用 | 任何 | 可安全删除：`sc.exe delete ServiceName` |
| 是 | 有效 | LocalService | 可能合法，进一步调查 |
| 是 | 未签名 | LocalSystem | 高风险 — 隔离并调查 |
| 是 | 有效 | LocalSystem | 检查发布者 — 可能合法 |

## 删除方法

```powershell
# 先停止（如果 exe 不存在可能失败）
sc.exe stop ServiceName

# 删除服务注册
sc.exe delete ServiceName
```

如果 `sc.exe delete` 没有输出但注册表键已消失，说明删除成功。
