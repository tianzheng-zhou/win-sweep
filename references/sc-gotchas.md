# PowerShell & sc.exe Common Gotchas

Common mistakes when AI generates PowerShell code and special pitfalls in Windows service management.
This document covers two categories: **PowerShell language gotchas** (common AI mistakes) and **sc.exe-specific gotchas**.

---

## PowerShell Language Gotchas (Common AI Mistakes)

### 1. `sc` is an Alias for `Set-Content`, Not sc.exe

AI frequently writes `sc config ...`, which PowerShell parses as `Set-Content`, causing cryptic errors.

```powershell
# Wrong — calls Set-Content, not sc.exe
sc config "ServiceName" start= demand

# Correct — always use the full name sc.exe
sc.exe config "ServiceName" start= demand
```

**Iron rule: In PowerShell, always write `sc.exe`, never `sc`.**

### 2. `&&` Is Not Supported (PowerShell 5.1)

AI is heavily trained on bash/shell and frequently uses `&&`. PowerShell 5.1 does not support it.

```powershell
# Wrong — syntax error in PowerShell 5.1
sc.exe stop "Svc" && sc.exe config "Svc" start= disabled

# Correct — use semicolons (unconditional execution)
sc.exe stop "Svc"; sc.exe config "Svc" start= disabled

# Correct — use if to check previous command success
sc.exe stop "Svc"
if ($LASTEXITCODE -eq 0) { sc.exe config "Svc" start= disabled }
```

> PowerShell 7.0+ supports `&&` and `||`, but this project targets 5.1.

### 3. Comparison Operators Are Not `==` `!=` `>` `<`

AI tends to generate C/Python/JS-style comparison operators, which PowerShell does not recognize.

```powershell
# Wrong — these are not comparison operators in PowerShell
if ($a == 0) { ... }        # Syntax error
if ($a != "hello") { ... }  # Syntax error
if ($a > 5) { ... }         # NOT comparison — redirects output to a file named "5"!

# Correct
if ($a -eq 0) { ... }
if ($a -ne "hello") { ... }
if ($a -gt 5) { ... }
```

| Meaning | Wrong | Correct |
|---------|-------|---------|
| Equal | `==` | `-eq` |
| Not equal | `!=` | `-ne` |
| Greater than | `>` | `-gt` |
| Less than | `<` | `-lt` |
| Greater or equal | `>=` | `-ge` |
| Less or equal | `<=` | `-le` |
| Contains | `in` | `-contains` or `-in` |
| Regex match | `~` | `-match` |

**Especially dangerous**: `$a > 5` does NOT produce an error — it silently redirects `$a`'s value into a file named `5`!

### 4. Function Calls Don't Use Parentheses or Commas

AI tends to write method-call style function invocations, which have completely different semantics in PowerShell.

```powershell
# Wrong — the comma creates a single array as the first argument, not two separate arguments
Set-Service -Name "Svc" -StartupType Manual
# The above is correct, but if AI writes:
MyFunction("arg1", "arg2")   # Wrong! Passes a single array with two elements

# Correct — function arguments are space-separated
MyFunction "arg1" "arg2"
MyFunction -Param1 "arg1" -Param2 "arg2"
```

### 5. Single Quotes vs Double Quotes

AI often uses single quotes when variable expansion is needed, or double quotes when it is not.

```powershell
# Single quotes — literal output, no variable expansion
$name = 'World'
'Hello $name'          # Output: Hello $name

# Double quotes — expands variables and escape characters
"Hello $name"          # Output: Hello World

# Service names containing $ must use single quotes (prevent variable expansion)
sc.exe config 'MSSQL$INSTANCE' start= demand    # Correct
sc.exe config "MSSQL$INSTANCE" start= demand     # Wrong — $INSTANCE treated as variable
sc.exe config "MSSQL`$INSTANCE" start= demand    # Correct — backtick escapes $
```

### 6. Single Object vs Array (Pipeline Unwrapping Gotcha)

PowerShell pipelines automatically unwrap arrays. When a command returns only one result, it returns the object, not an array.

```powershell
# Dangerous — if only one service matches, $services is NOT an array
$services = Get-CimInstance Win32_Service -Filter "StartMode='Auto'"
$services.Count   # May return unexpected value for single objects (object's own Count property or $null)

# Safe — force-wrap in array with @()
$services = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto'")
$services.Count   # Always correct: 0 items = 0, 1 item = 1, N items = N
```

**Rule: Whenever you need `.Count` or index access on results, wrap with `@()`.**

### 7. `$LASTEXITCODE` vs `$?`

AI frequently conflates these two — they mean different things.

```powershell
# $? — Whether the PowerShell command succeeded (cmdlet terminating/non-terminating error)
# $LASTEXITCODE — Exit code of the last native program (.exe)

# Check if sc.exe succeeded
sc.exe config "Svc" start= demand
if ($LASTEXITCODE -ne 0) {
    Write-Error "sc.exe failed with exit code: $LASTEXITCODE"
}

# Note: $? is unreliable for native programs (almost always True in PS 5.1)
# Always use $LASTEXITCODE to check .exe execution results
```

### 8. `Get-WmiObject` Is Deprecated

AI training data heavily uses `Get-WmiObject`, which is removed in PowerShell 7.

```powershell
# Deprecated — PS7 will error
Get-WmiObject Win32_Service -Filter "Name='Svc'"

# Recommended — works in both versions
Get-CimInstance Win32_Service -Filter "Name='Svc'"
```

| Old cmdlet | Replacement |
|-----------|-------------|
| `Get-WmiObject` | `Get-CimInstance` |
| `Set-WmiInstance` | `Set-CimInstance` |
| `Invoke-WmiMethod` | `Invoke-CimMethod` |

### 9. Native Program stderr Triggers Terminating Error

When `$ErrorActionPreference = 'Stop'`, native program stderr output is treated as an error by PowerShell, triggering catch blocks.

```powershell
# Problem: sc.exe warning messages go to stderr, causing unexpected termination
$ErrorActionPreference = 'Stop'
$output = sc.exe qfailure "Svc" 2>&1   # May throw terminating error

# Safe approach: control ErrorAction independently
$output = sc.exe qfailure "Svc" 2>&1 | Out-String
# Or temporarily restore default behavior
$prevEA = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = sc.exe qfailure "Svc" 2>&1 | Out-String
$ErrorActionPreference = $prevEA
```

### 10. Registry Paths: PowerShell vs reg.exe

Two completely different path syntaxes:

```powershell
# PowerShell cmdlets — require PSDrive prefix + colon
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Svc"
Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# reg.exe — no colon or backslash prefix
reg query "HKLM\SYSTEM\CurrentControlSet\Services\Svc"
reg export "HKLM\SYSTEM\CurrentControlSet\Services\Svc" backup.reg

# Common AI mistake: mixing the two syntaxes
Test-Path "HKLM\SYSTEM\..."     # Wrong — missing colon, Test-Path treats as relative path
reg query "HKLM:\SYSTEM\..."    # Wrong — reg.exe doesn't recognize PSDrive syntax
```

### 11. `-match` Is Case-Insensitive by Default

```powershell
# These two are equivalent — AI sometimes adds unnecessary .ToLower()
"Hello" -match "hello"    # True (case-insensitive by default)
"Hello".ToLower() -match "hello"  # Redundant

# Use -cmatch when case sensitivity is needed
"Hello" -cmatch "hello"   # False
```

### 12. `Format-*` Output Cannot Be Further Piped

```powershell
# Wrong — Format-Table output is formatting objects, not raw data
Get-Service | Format-Table | Where-Object { $_.Status -eq 'Running' }  # Does not work

# Correct — filter first, format at the very end (Format-* always goes last in the pipeline)
Get-Service | Where-Object { $_.Status -eq 'Running' } | Format-Table
```

### 13. Embedding Object Properties in Strings

```powershell
$svc = Get-CimInstance Win32_Service -Filter "Name='wuauserv'"

# Wrong — only $svc is expanded, .Name is treated as literal text
"Service name: $svc.Name"          # Output: Service name: <entire object ToString()>.Name

# Correct — use subexpression
"Service name: $($svc.Name)"       # Output: Service name: wuauserv
```

---

## sc.exe-Specific Gotchas

### Equals Sign Must Be Followed by a Space

`sc.exe config` requires a space after the equals sign. This is sc.exe's own syntax requirement.

```powershell
# Correct
sc.exe config "ServiceName" start= demand

# Wrong — will silently fail or error
sc.exe config "ServiceName" start=demand
```

### Service Names Containing `$`

SQL Server named instances use the `MSSQL$InstanceName` format.

```powershell
# Correct — single quotes prevent variable expansion
sc.exe config 'MSSQL$TEW_SQLEXPRESS' start= demand

# Correct — backtick escapes $
sc.exe config "MSSQL`$TEW_SQLEXPRESS" start= demand

# Wrong — $TEW_SQLEXPRESS is treated as a variable (resolves to empty)
sc.exe config "MSSQL$TEW_SQLEXPRESS" start= demand
```

### sc.exe vs Set-Service Comparison

| Feature | sc.exe | Set-Service |
|---------|--------|-------------|
| Startup mode | `start= demand` | `-StartupType Manual` |
| Dollar sign | Requires quoting | Same issue |
| Delete service | `sc.exe delete` | Not supported |
| Query failure policy | `sc.exe qfailure` | Not supported |
| Remote machine | `sc.exe \\server` | `-ComputerName` |

Recommend using `sc.exe` for consistency — it supports service deletion and failure policy queries, with predictable behavior across PowerShell versions.

### Silent Failures

`sc.exe config` may appear to succeed but not actually take effect:
- **Misspelled service name** — Still outputs `[SC] ChangeServiceConfig SUCCESS`, but modified a non-existent target (created a new entry)
- **`$` was expanded** — `$` in the service name was parsed by PowerShell as an empty variable
- **Insufficient privileges** — Some services are protected by SDDL; even normal admin cannot modify them

**Always verify**:
```powershell
# Confirm immediately after modification
Get-CimInstance Win32_Service -Filter "Name='ServiceName'" |
    Select-Object Name, StartMode
```

### sc.exe delete Special Behavior

```powershell
# After deletion the service may still appear (marked as "DELETE_PENDING")
sc.exe delete "ServiceName"

# If the service is running, stop it first
sc.exe stop "ServiceName"
sc.exe delete "ServiceName"

# Verify: registry key gone = deletion succeeded (may need reboot to fully clean up)
Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\ServiceName"
```

### 14. Multi-Line `if/else` Blocks Break When Pasted into Terminal

When AI generates multi-line `if/else` code and the user pastes it into an interactive PowerShell terminal (including VS Code integrated terminal), each line is executed independently. The `else` block becomes a standalone statement and errors out.

```powershell
# This works in a .ps1 script, but BREAKS when pasted into terminal:
if (Test-Path $path) {
    Remove-Item $path
}
else {
    Write-Host "Not found"
}
# Terminal error: "else" is not recognized — because "}" on the previous line
# already closed the statement.

# Safe for terminal paste — keep else on the same line as closing brace:
if (Test-Path $path) {
    Remove-Item $path
} else {
    Write-Host "Not found"
}

# Even safer — single line or pre-compute:
$exists = Test-Path $path
if ($exists) { Remove-Item $path } else { Write-Host "Not found" }
```

**Rule: When generating code that may be pasted interactively, always put `} else {`, `} elseif {`, `} catch {`, `} finally {` on the same line as the closing brace `}`.**

This also affects `try/catch/finally`, `do/while`, and `switch` blocks. The underlying issue is that PowerShell's interactive parser treats a line ending with `}` as a complete statement.

---

## AI Self-Check Checklist

After generating PowerShell code, verify against this checklist:

- [ ] Did you write `sc.exe` or just `sc`?
- [ ] Did you use `&&`? PowerShell 5.1 does not support it
- [ ] Are comparison operators `-eq` / `-ne` / `-gt` or `==` / `!=` / `>`?
- [ ] Is `>` a redirection or did you mean it as a greater-than comparison?
- [ ] Are function arguments separated by spaces? Did you write method-call style `Func(a, b)`?
- [ ] Are strings containing `$` wrapped in single quotes?
- [ ] Are results that need `.Count` wrapped in `@()`?
- [ ] Are you checking native program results with `$LASTEXITCODE` or `$?`?
- [ ] Registry paths: PowerShell uses `HKLM:\`, reg.exe uses `HKLM\`?
- [ ] Is `Format-Table` / `Format-List` at the end of the pipeline?
- [ ] Are property accesses inside double-quoted strings wrapped in `$()` sub-expressions?
- [ ] Are `} else {`, `} catch {`, `} finally {` on the same line as `}`? (Terminal paste safety)
