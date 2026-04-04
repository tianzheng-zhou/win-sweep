# 可疑服务排查清单

本文档为 AI 提供**系统化的排查框架**，用于识别和处理未知、残留或潜在恶意的 Windows 服务。

---

## 风险信号与评分

每个信号有一个权重分。对单个服务累加所有命中的信号分值，得出综合风险。

| # | 信号 | 分值 | 说明 |
|---|------|------|------|
| S1 | 可执行文件路径不存在 | +3 | 软件已卸载但服务注册残留 |
| S2 | 可执行文件未签名 | +3 | 缺少数字签名 — 无法验证来源 |
| S3 | 签名无效或已过期 | +4 | 比未签名更可疑 — 可能被篡改 |
| S4 | 以 `LocalSystem` 运行 | +2 | 最高权限；合法服务也常用，需结合其他信号 |
| S5 | 配置了失败自动重启 | +1 | 持久化机制；合法服务也用，单独不构成高风险 |
| S6 | 路径在 `ProgramData`、`Temp`、`AppData` 或 `Downloads` | +3 | 用户可写目录 — 合法服务很少装在这里 |
| S7 | 服务名为随机字符 / 含乱码 / 非 ASCII | +4 | 恶意软件/广告软件的典型命名 |
| S8 | 服务描述为空 | +1 | 正规软件通常会填写描述 |
| S9 | `ImagePath` 含可疑参数（如 `-encode`、`-hidden`、`bypass`） | +5 | 强烈暗示恶意行为 |
| S10 | 可执行文件创建时间与系统安装时间不符，且非近期已知安装 | +2 | 可能是被投放的文件 |
| S11 | 注册表中无 `Description` 和 `DisplayName` 值 | +2 | 极度精简的注册 — 正规软件不会这样 |
| S12 | DLL 服务（`svchost.exe -k`）指向不存在的 DLL | +4 | 残留或劫持 |

### 风险等级

| 累计分值 | 等级 | 建议动作 |
|----------|------|----------|
| 1-3 | 低 | 记录，暂不处理；可能是合法软件的非典型配置 |
| 4-6 | 中 | 深入调查（执行下方排查流程），确认后处理 |
| 7+ | 高 | 强烈建议停止并移除；若文件存在，先备份供取证 |

---

## 排查流程

对每个标记为可疑的服务，按顺序执行以下步骤。

### 第 1 步：基本信息采集

一次性获取服务的关键属性：

```powershell
Get-CimInstance Win32_Service -Filter "Name='ServiceName'" |
    Select-Object Name, DisplayName, Description, PathName, StartName,
                  StartMode, State, ProcessId
```

### 第 2 步：可执行文件检查

从 `PathName` 中提取实际路径（去掉参数和引号），然后：

```powershell
# 提取路径（处理带参数的 ImagePath）
$imagePath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\ServiceName").ImagePath
# 手动检查 $imagePath 中可执行文件的实际路径

# 文件是否存在
Test-Path "C:\actual\path\to\executable.exe"

# 文件详情
Get-Item "C:\actual\path\to\executable.exe" | Select-Object FullName, CreationTime, LastWriteTime, Length
```

**如果文件不存在** → 累加 S1，跳到决策矩阵。

### 第 3 步：签名验证

```powershell
Get-AuthenticodeSignature "C:\actual\path\to\executable.exe"
```

| Status | 含义 |
|--------|------|
| `Valid` | 签名有效 — 记录发布者（Subject），继续检查 |
| `NotSigned` | 未签名 — 累加 S2 |
| `HashMismatch` | 文件被修改 — 累加 S3，高度警惕 |
| `NotTrusted` / `UnknownError` | 证书链异常 — 累加 S3 |

### 第 4 步：运行账户与持久化

```powershell
# 运行账户
Get-CimInstance Win32_Service -Filter "Name='ServiceName'" | Select-Object StartName

# 失败重启策略
sc.exe qfailure "ServiceName"
```

`sc.exe qfailure` 输出解读：
- `RESTART -- Delay = xxx`：配置了自动重启 → 累加 S5
- `RUN PROCESS`：失败时运行其他程序 → 额外关注该程序路径
- `(空)` 或全是 `-- Delay = 0`：无特殊配置

### 第 5 步：依赖关系

```powershell
# 该服务依赖谁
sc.exe qc "ServiceName"       # DEPENDENCIES 字段

# 谁依赖该服务
sc.exe enumdepend "ServiceName"
```

如果有其他服务依赖它 → 删除前需评估影响。

### 第 6 步：网络活动（可选，针对高风险）

如果服务正在运行且风险分较高：

```powershell
# 查看该进程的网络连接
$pid = (Get-CimInstance Win32_Service -Filter "Name='ServiceName'").ProcessId
Get-NetTCPConnection -OwningProcess $pid -ErrorAction SilentlyContinue |
    Select-Object LocalPort, RemoteAddress, RemotePort, State
```

发现对外连接 → 记录远程地址，提升风险等级。

---

## 决策矩阵

根据排查结果，对照以下矩阵决定处理方式：

| 文件存在 | 签名状态 | 运行账户 | 风险分 | 处理方式 |
|----------|----------|----------|--------|----------|
| 否 | — | 任何 | 3+ | **删除**服务注册（残留，无功能） |
| 是 | Valid + 知名发布者 | LocalService / NetworkService | 1-3 | **合法** — 不处理或按 service-rules 优化 |
| 是 | Valid + 知名发布者 | LocalSystem | 1-3 | **可能合法** — 微软/大厂驱动常用 LocalSystem，确认发布者后放行 |
| 是 | Valid + 未知发布者 | 任何 | 4-6 | **调查** — 搜索发布者名称，确认是否为已知软件 |
| 是 | NotSigned | LocalService | 4-6 | **可疑** — 部分小型合法软件不签名，需确认来源 |
| 是 | NotSigned | LocalSystem | 7+ | **高风险** — 停止服务，备份文件供取证，建议删除 |
| 是 | HashMismatch / NotTrusted | 任何 | 7+ | **高风险** — 文件可能被篡改，立即停止，备份取证 |

---

## 常见误报

以下情况会触发风险信号但通常是合法的，排查时应优先排除：

| 场景 | 触发信号 | 如何确认是误报 |
|------|----------|----------------|
| 微软自带服务以 LocalSystem 运行 | S4 | 路径在 `System32`，签名有效且发布者为 `Microsoft` |
| 驱动服务（Type = Kernel Driver） | S8（无描述） | `sc.exe qc` 显示 TYPE 为 `KERNEL_DRIVER`，路径在 `drivers\` |
| 开发工具本地服务（Node.js、Python） | S2（未签名），S6（AppData） | 路径匹配已安装的开发工具目录 |
| .NET / Java 服务包装器 | S2（主exe签名但wrapper未签名） | `PathName` 指向 `dotnet.exe` 或 `java.exe` + 应用 DLL/JAR |
| Windows 内置但默认禁用的服务 | S8（无描述） | 服务名在已知 Windows 服务列表中 |

---

## 处理操作

### 删除前的安全步骤

```powershell
# 1. 备份服务注册表项（可用于恢复）
reg export "HKLM\SYSTEM\CurrentControlSet\Services\ServiceName" "$env:TEMP\svc-backup-ServiceName.reg"

# 2. 如果文件存在且需取证，复制到安全位置
# Copy-Item "C:\path\to\suspicious.exe" "$env:TEMP\quarantine\"

# 3. 停止服务（文件不存在时可能报错，可忽略）
sc.exe stop "ServiceName"

# 4. 检查是否有依赖（有依赖则三思）
sc.exe enumdepend "ServiceName"

# 5. 删除服务注册
sc.exe delete "ServiceName"
```

### 验证删除结果

```powershell
# 确认注册表键已消失
Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\ServiceName"
# 预期输出：False

# 如果返回 True，服务可能标记为"待删除"，重启后生效
```

### 回滚

如果误删，用之前导出的 `.reg` 文件恢复：

```powershell
reg import "$env:TEMP\svc-backup-ServiceName.reg"
# 恢复后需重启才能生效
```

---

## 快速参考命令

| 目的 | 命令 |
|------|------|
| 列出所有非 Microsoft 服务 | `Get-CimInstance Win32_Service \| Where-Object { $_.PathName -and $_.PathName -notmatch 'windows\\system32' }` |
| 列出所有以 LocalSystem 运行的第三方服务 | `Get-CimInstance Win32_Service \| Where-Object { $_.StartName -eq 'LocalSystem' -and $_.PathName -notmatch 'system32' }` |
| 列出可执行文件不存在的服务 | 需遍历 + `Test-Path`（见 detect-suspicious.ps1） |
| 批量检查签名 | `Get-CimInstance Win32_Service \| ForEach-Object { ... Get-AuthenticodeSignature }` |
