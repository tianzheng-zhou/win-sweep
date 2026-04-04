# PowerShell 和 sc.exe 常见陷阱

AI 生成 PowerShell 代码时的高频错误和 Windows 服务管理的特殊坑。
本文档覆盖两类问题：**PowerShell 语言陷阱**（AI 的通病）和 **sc.exe 专项陷阱**。

---

## PowerShell 语言陷阱（AI 高频错误）

### 1. `sc` 是 `Set-Content` 的别名，不是 sc.exe

AI 经常写 `sc config ...`，在 PowerShell 中会被解析为 `Set-Content`，导致莫名错误。

```powershell
# 错误 — 调用的是 Set-Content，不是 sc.exe
sc config "ServiceName" start= demand

# 正确 — 始终用 sc.exe 的完整名称
sc.exe config "ServiceName" start= demand
```

**铁律：在 PowerShell 中操作服务，永远写 `sc.exe`，不要写 `sc`。**

### 2. 不支持 `&&` 链接命令（PowerShell 5.1）

AI 大量训练自 bash/shell，频繁使用 `&&`。PowerShell 5.1 不支持。

```powershell
# 错误 — PowerShell 5.1 语法错误
sc.exe stop "Svc" && sc.exe config "Svc" start= disabled

# 正确 — 用分号链接（无条件执行）
sc.exe stop "Svc"; sc.exe config "Svc" start= disabled

# 正确 — 用 if 检查上一条是否成功
sc.exe stop "Svc"
if ($LASTEXITCODE -eq 0) { sc.exe config "Svc" start= disabled }
```

> PowerShell 7.0+ 支持 `&&` 和 `||`，但本项目面向 5.1。

### 3. 比较运算符不是 `==` `!=` `>` `<`

AI 习惯生成 C/Python/JS 风格的比较运算符，PowerShell 不认。

```powershell
# 错误 — 这些在 PowerShell 中不是比较运算符
if ($a == 0) { ... }        # 语法错误
if ($a != "hello") { ... }  # 语法错误
if ($a > 5) { ... }         # 不是比较，是重定向到文件 "5"！

# 正确
if ($a -eq 0) { ... }
if ($a -ne "hello") { ... }
if ($a -gt 5) { ... }
```

| 含义 | 错误写法 | 正确写法 |
|------|----------|----------|
| 等于 | `==` | `-eq` |
| 不等于 | `!=` | `-ne` |
| 大于 | `>` | `-gt` |
| 小于 | `<` | `-lt` |
| 大于等于 | `>=` | `-ge` |
| 小于等于 | `<=` | `-le` |
| 包含 | `in` | `-contains` 或 `-in` |
| 匹配正则 | `~` | `-match` |

**特别危险**：`$a > 5` 不会报错，而是把 `$a` 的值重定向写入名为 `5` 的文件！

### 4. 函数调用不用括号和逗号

AI 容易写出方法调用风格的函数调用，在 PowerShell 中语义完全不同。

```powershell
# 错误 — 逗号创建了一个数组作为第一个参数，而非两个独立参数
Set-Service -Name "Svc" -StartupType Manual
# 上面是对的，但如果 AI 写成：
MyFunction("arg1", "arg2")   # 错误！传入的是一个包含两个元素的数组

# 正确 — 函数参数用空格分隔
MyFunction "arg1" "arg2"
MyFunction -Param1 "arg1" -Param2 "arg2"
```

### 5. 单引号 vs 双引号

AI 经常在需要变量展开时使用单引号，或在不需要时使用双引号。

```powershell
# 单引号 — 原样输出，不展开变量
$name = 'World'
'Hello $name'          # 输出: Hello $name

# 双引号 — 展开变量和转义字符
"Hello $name"          # 输出: Hello World

# 含 $ 的服务名必须用单引号（阻止变量展开）
sc.exe config 'MSSQL$INSTANCE' start= demand    # 正确
sc.exe config "MSSQL$INSTANCE" start= demand     # 错误 — $INSTANCE 被当作变量
sc.exe config "MSSQL`$INSTANCE" start= demand    # 正确 — 反引号转义
```

### 6. 单个对象 vs 数组（管道展开陷阱）

PowerShell 管道会自动展开数组。当命令只返回一个结果时，返回的是对象而非数组。

```powershell
# 危险 — 如果只有一个服务匹配，$services 不是数组
$services = Get-CimInstance Win32_Service -Filter "StartMode='Auto'"
$services.Count   # 单个对象时可能返回意外值（对象自身的 Count 属性或 $null）

# 安全 — 用 @() 强制包装为数组
$services = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto'")
$services.Count   # 始终正确：0 个 = 0，1 个 = 1，N 个 = N
```

**规则：凡是要对返回结果做 `.Count` 或索引访问的，都用 `@()` 包裹。**

### 7. `$LASTEXITCODE` vs `$?`

AI 经常混用这两个，它们含义不同。

```powershell
# $? — PowerShell 命令是否成功（cmdlet 的 terminating/non-terminating error）
# $LASTEXITCODE — 上一个原生程序（.exe）的退出码

# 检查 sc.exe 是否成功
sc.exe config "Svc" start= demand
if ($LASTEXITCODE -ne 0) {
    Write-Error "sc.exe 失败，退出码: $LASTEXITCODE"
}

# 注意：$? 对原生程序不可靠（PS5.1 中几乎总是 True）
# 永远用 $LASTEXITCODE 检查 .exe 的执行结果
```

### 8. `Get-WmiObject` 已过时

AI 训练数据中大量使用 `Get-WmiObject`，它在 PowerShell 7 中已移除。

```powershell
# 过时 — PS7 会报错
Get-WmiObject Win32_Service -Filter "Name='Svc'"

# 推荐 — 两个版本都支持
Get-CimInstance Win32_Service -Filter "Name='Svc'"
```

| 旧 cmdlet | 替代 |
|-----------|------|
| `Get-WmiObject` | `Get-CimInstance` |
| `Set-WmiInstance` | `Set-CimInstance` |
| `Invoke-WmiMethod` | `Invoke-CimMethod` |

### 9. 原生程序 stderr 触发终止错误

当 `$ErrorActionPreference = 'Stop'` 时，原生程序写入 stderr 的内容会被 PowerShell 当作错误，触发 catch 块。

```powershell
# 问题：sc.exe 的警告信息走 stderr，导致意外终止
$ErrorActionPreference = 'Stop'
$output = sc.exe qfailure "Svc" 2>&1   # 可能抛出 terminating error

# 安全写法：独立控制 ErrorAction
$output = sc.exe qfailure "Svc" 2>&1 | Out-String
# 或临时恢复默认行为
$prevEA = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = sc.exe qfailure "Svc" 2>&1 | Out-String
$ErrorActionPreference = $prevEA
```

### 10. 注册表路径：PowerShell vs reg.exe

两套完全不同的路径语法：

```powershell
# PowerShell cmdlet — 需要 PSDrive 前缀 + 冒号
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Svc"
Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# reg.exe — 不要冒号和反斜杠前缀
reg query "HKLM\SYSTEM\CurrentControlSet\Services\Svc"
reg export "HKLM\SYSTEM\CurrentControlSet\Services\Svc" backup.reg

# 常见 AI 错误：混用两种语法
Test-Path "HKLM\SYSTEM\..."     # 错误 — 缺少冒号，Test-Path 当作相对路径
reg query "HKLM:\SYSTEM\..."    # 错误 — reg.exe 不认 PSDrive 语法
```

### 11. `-match` 默认大小写不敏感

```powershell
# 这两个等价 — AI 有时会多此一举加 .ToLower()
"Hello" -match "hello"    # True（默认不区分大小写）
"Hello".ToLower() -match "hello"  # 多余

# 需要区分大小写时
"Hello" -cmatch "hello"   # False
```

### 12. `Format-*` 的输出不能再管道处理

```powershell
# 错误 — Format-Table 的输出是格式化对象，不是原始数据
Get-Service | Format-Table | Where-Object { $_.Status -eq 'Running' }  # 不工作

# 正确 — 先过滤，最后格式化（Format-* 永远放管道最末端）
Get-Service | Where-Object { $_.Status -eq 'Running' } | Format-Table
```

### 13. 字符串中嵌入对象属性

```powershell
$svc = Get-CimInstance Win32_Service -Filter "Name='wuauserv'"

# 错误 — 只展开 $svc，.Name 被当作普通文本
"服务名: $svc.Name"          # 输出: 服务名: <整个对象的ToString()>.Name

# 正确 — 用子表达式
"服务名: $($svc.Name)"       # 输出: 服务名: wuauserv
```

---

## sc.exe 专项陷阱

### 等号后必须有空格

`sc.exe config` 要求等号后面有一个空格。这是 sc.exe 自己的语法规定。

```powershell
# 正确
sc.exe config "ServiceName" start= demand

# 错误 — 会静默失败或报错
sc.exe config "ServiceName" start=demand
```

### 服务名包含 `$`

SQL Server 命名实例使用 `MSSQL$实例名` 格式。

```powershell
# 正确 — 单引号阻止变量展开
sc.exe config 'MSSQL$TEW_SQLEXPRESS' start= demand

# 正确 — 反引号转义 $
sc.exe config "MSSQL`$TEW_SQLEXPRESS" start= demand

# 错误 — $TEW_SQLEXPRESS 被当作变量（解析为空）
sc.exe config "MSSQL$TEW_SQLEXPRESS" start= demand
```

### sc.exe 与 Set-Service 对比

| 功能 | sc.exe | Set-Service |
|------|--------|-------------|
| 启动模式 | `start= demand` | `-StartupType Manual` |
| 美元符号 | 需要引号包裹 | 同样问题 |
| 删除服务 | `sc.exe delete` | 不支持 |
| 查询失败策略 | `sc.exe qfailure` | 不支持 |
| 远程机器 | `sc.exe \\server` | `-ComputerName` |

推荐使用 `sc.exe` 保持一致性 — 它支持删除服务和查询失败策略，且跨 PowerShell 版本行为可预测。

### 静默失败

`sc.exe config` 可能看起来成功但实际未生效：
- **服务名拼错** — 仍输出 `[SC] ChangeServiceConfig SUCCESS`，但修改了不存在的目标（创建了新条目）
- **`$` 被展开** — 服务名中的 `$` 被 PowerShell 解析为空变量
- **权限不足** — 部分服务受 SDDL 保护，普通管理员也无法修改

**始终验证**：
```powershell
# 修改后立即确认
Get-CimInstance Win32_Service -Filter "Name='ServiceName'" |
    Select-Object Name, StartMode
```

### sc.exe delete 的特殊行为

```powershell
# 删除后服务可能仍显示（标记为 "DELETE_PENDING"）
sc.exe delete "ServiceName"

# 如果服务正在运行，需要先停止
sc.exe stop "ServiceName"
sc.exe delete "ServiceName"

# 验证：注册表键消失 = 删除成功（可能需要重启才彻底清理）
Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\ServiceName"
```

---

## AI 自检清单

生成 PowerShell 代码后，对照以下清单检查：

- [ ] 写的是 `sc.exe` 还是 `sc`？
- [ ] 用了 `&&` 吗？PowerShell 5.1 不支持
- [ ] 比较运算符是 `-eq` / `-ne` / `-gt` 还是 `==` / `!=` / `>`？
- [ ] `>` 是重定向还是你以为的大于比较？
- [ ] 函数参数用空格分隔了吗？有没有写成 `Func(a, b)` 的方法调用风格？
- [ ] 含 `$` 的字符串用单引号了吗？
- [ ] 需要 `.Count` 的结果用 `@()` 包裹了吗？
- [ ] 检查原生程序结果用的是 `$LASTEXITCODE` 还是 `$?`？
- [ ] 注册表路径：PowerShell 用 `HKLM:\`，reg.exe 用 `HKLM\`？
- [ ] `Format-Table` / `Format-List` 放在管道最后了吗？
- [ ] 双引号中访问属性用了 `$()` 子表达式吗？
