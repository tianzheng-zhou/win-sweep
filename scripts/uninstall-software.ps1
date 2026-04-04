#Requires -Version 5.1
<#
.SYNOPSIS
    win-sweep software removal — list candidates, attempt uninstall, and clean up leftovers.
.DESCRIPTION
    Three modes of operation:
    - List: Scan installed software from registry, generate a "recommended uninstall list."
    - Uninstall: Attempt to invoke the uninstaller from the terminal. WARNING: This is unreliable
      for many programs (GUI-only uninstallers, guardian processes, kernel driver locks). The
      preferred workflow is: List → user manually uninstalls via Settings/Control Panel → Cleanup.
      Includes timeout protection to prevent indefinite hangs.
    - Cleanup: After uninstall (manual or automated), scan for leftover artifacts — orphaned
      services, scheduled tasks, startup items, program directories, and AppData folders.
      This is the primary value of this script.
.PARAMETER Action
    Operation mode: List, Uninstall, or Cleanup.
.PARAMETER Programs
    JSON array of programs to uninstall. Each object must have a "Name" key matching
    the registry DisplayName (exact or substring match).
    Example: '[{"Name":"Bonjour"},{"Name":"Adobe Flash"}]'
.PARAMETER Quiet
    Attempt quiet/silent uninstall when available.
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for each uninstaller process (default: 120).
    If the uninstaller does not exit within this time, it will be killed.
    This prevents GUI uninstallers and hung processes from freezing the terminal.
.PARAMETER CleanupTarget
    For Cleanup action: the software name(s) to scan leftovers for.
    Example: 'Adobe Flash','Bonjour'
.PARAMETER SkipUninstaller
    For Cleanup action: skip running the uninstaller, only scan and remove leftovers.
    Useful when the software has already been uninstalled but left residue behind.
.NOTES
    ⚠️ IMPORTANT: Terminal-based uninstall is unreliable for many programs, especially:
    - Chinese rogue software (360, 鲁大师, 2345, etc.) — GUI-only, guardian processes, kernel locks
    - Bloated AV products (McAfee, Norton, Avast) — require vendor-specific removal tools
    - Any software with no silent/quiet uninstall mode
    The recommended workflow is to use List + Cleanup, with the user doing the actual
    uninstall manually through Settings > Apps or Control Panel.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('List', 'Uninstall', 'Cleanup')]
    [string]$Action = 'List',

    [string]$Programs,

    [switch]$Quiet,

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 120,

    [string[]]$CleanupTarget,

    [switch]$SkipUninstaller
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# ── Registry paths for installed software ──
$regPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

function Get-InstalledSoftware {
    $regPaths | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() } |
        Select-Object @{N='DisplayName';       E={$_.DisplayName.Trim()}},
                      DisplayVersion,
                      Publisher,
                      @{N='SizeMB';            E={if ($_.EstimatedSize) {[math]::Round($_.EstimatedSize / 1024, 1)} else {$null}}},
                      InstallDate,
                      UninstallString,
                      QuietUninstallString,
                      InstallLocation,
                      @{N='RegistryPath';      E={$_.PSPath}} |
        Sort-Object DisplayName
}

function Find-SoftwareEntry([string]$Name) {
    $all = Get-InstalledSoftware
    # Try exact match first, then substring
    $match = $all | Where-Object { $_.DisplayName -eq $Name }
    if (-not $match) {
        $match = $all | Where-Object { $_.DisplayName -like "*$Name*" }
    }
    return $match
}

# ── List ──
switch ($Action) {
    'List' {
        Write-Host "`nInstalled Software:" -ForegroundColor Cyan
        $software = Get-InstalledSoftware
        Write-Host "  Total: $($software.Count) programs`n" -ForegroundColor Yellow

        $software |
            Select-Object DisplayName, DisplayVersion, Publisher, SizeMB, InstallDate |
            Format-Table -AutoSize -Wrap

        # Also check for winget availability
        $wingetAvailable = $false
        try {
            $null = Get-Command winget -ErrorAction Stop
            $wingetAvailable = $true
        } catch {}

        if ($wingetAvailable) {
            Write-Host "  [INFO] winget is available — can be used for cleaner uninstalls." -ForegroundColor Green
        } else {
            Write-Host "  [INFO] winget not found — will use native uninstallers." -ForegroundColor DarkYellow
        }
    }

    'Uninstall' {
        Write-Host "`n" -NoNewline
        Write-Host ('!' * 60) -ForegroundColor Yellow
        Write-Host ' WARNING: Terminal-based uninstall has significant limitations' -ForegroundColor Yellow
        Write-Host ('!' * 60) -ForegroundColor Yellow
        Write-Host @"

  Many programs (especially rogue software) have GUI-only uninstallers
  that will hang the terminal or fail silently. The recommended workflow:
    1. Use this script's List mode to identify what to remove
    2. Uninstall manually via Settings > Apps or Control Panel
    3. Use this script's Cleanup mode to remove leftovers

  Proceeding with terminal uninstall (timeout: $TimeoutSeconds seconds per program)...

"@ -ForegroundColor Yellow

        if (-not $Programs) {
            Write-Error "Uninstall action requires the -Programs parameter (JSON array)."
            exit 1
        }

        try {
            $programList = $Programs | ConvertFrom-Json
        } catch {
            Write-Error "Failed to parse Programs parameter. Format: '[{`"Name`":`"ProgramName`"}]'"
            exit 1
        }

        if ($programList.Count -eq 0) {
            Write-Host "No programs specified." -ForegroundColor Yellow
            exit 0
        }

        # Check winget availability
        $wingetAvailable = $false
        try {
            $null = Get-Command winget -ErrorAction Stop
            $wingetAvailable = $true
        } catch {}

        $results = @()

        foreach ($prog in $programList) {
            $name = $prog.Name
            Write-Host "`n─── Uninstalling: $name ───" -ForegroundColor Cyan

            $entries = Find-SoftwareEntry $name
            if (-not $entries) {
                Write-Host "  [SKIP] '$name' — not found in registry" -ForegroundColor DarkYellow
                $results += [PSCustomObject]@{ Name=$name; Status='NotFound'; Method='N/A' }
                continue
            }

            # If multiple matches, list them
            if (@($entries).Count -gt 1) {
                Write-Host "  [WARN] Multiple matches found:" -ForegroundColor Yellow
                $i = 0
                foreach ($e in $entries) {
                    $i++
                    Write-Host "    $i. $($e.DisplayName) ($($e.DisplayVersion))" -ForegroundColor Yellow
                }
                Write-Host "  Using first match: $($entries[0].DisplayName)" -ForegroundColor Yellow
                $entries = @($entries)[0]
            } else {
                $entries = @($entries)[0]
            }

            Write-Host "  Found: $($entries.DisplayName) v$($entries.DisplayVersion)" -ForegroundColor White

            # Strategy 1: Try winget first (cleanest and most reliable from terminal)
            $uninstalled = $false
            if ($wingetAvailable) {
                Write-Host "  Attempting winget uninstall (timeout: ${TimeoutSeconds}s)..." -ForegroundColor Gray
                try {
                    $wingetArgs = @('uninstall', '--name', $entries.DisplayName, '--accept-source-agreements')
                    if ($Quiet) { $wingetArgs += '--silent' }

                    $proc = Start-Process winget -ArgumentList ($wingetArgs -join ' ') -PassThru -NoNewWindow -ErrorAction Stop
                    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)

                    if (-not $exited) {
                        Write-Host "  [TIMEOUT] winget did not finish within ${TimeoutSeconds}s — killing process" -ForegroundColor Red
                        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                        Write-Host "  [INFO] Please uninstall '$($entries.DisplayName)' manually via Settings > Apps" -ForegroundColor Yellow
                        $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='Timeout'; Method='winget' }
                        continue
                    } elseif ($proc.ExitCode -eq 0) {
                        Write-Host "  [OK] Uninstalled via winget" -ForegroundColor Green
                        $uninstalled = $true
                        $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='Uninstalled'; Method='winget' }
                    } else {
                        Write-Host "  [INFO] winget failed (exit code: $($proc.ExitCode)), falling back to native uninstaller" -ForegroundColor DarkYellow
                    }
                } catch {
                    Write-Host "  [INFO] winget error, falling back to native uninstaller" -ForegroundColor DarkYellow
                }
            }

            # Strategy 2: Native uninstaller (with timeout protection)
            if (-not $uninstalled) {
                $uninstallCmd = if ($Quiet -and $entries.QuietUninstallString) {
                    $entries.QuietUninstallString
                } else {
                    $entries.UninstallString
                }

                if (-not $uninstallCmd) {
                    Write-Host "  [FAIL] No uninstall command found in registry" -ForegroundColor Red
                    Write-Host "  [INFO] Please uninstall '$($entries.DisplayName)' manually via Settings > Apps" -ForegroundColor Yellow
                    $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='NoUninstaller'; Method='N/A' }
                    continue
                }

                Write-Host "  Running: $uninstallCmd (timeout: ${TimeoutSeconds}s)" -ForegroundColor Gray

                try {
                    $proc = $null
                    # Parse the uninstall command — handle both EXE and MsiExec
                    if ($uninstallCmd -match 'MsiExec') {
                        # MSI-based uninstall
                        $msiArgs = $uninstallCmd -replace '^MsiExec\.exe\s*', ''
                        if ($Quiet -and $msiArgs -notmatch '/quiet|/qn') {
                            $msiArgs = "$msiArgs /quiet /norestart"
                        }
                        $proc = Start-Process msiexec.exe -ArgumentList $msiArgs -PassThru -ErrorAction Stop
                    } else {
                        # EXE-based uninstall
                        $proc = Start-Process cmd.exe -ArgumentList "/c `"$uninstallCmd`"" -PassThru -ErrorAction Stop
                    }

                    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)

                    if (-not $exited) {
                        Write-Host "  [TIMEOUT] Uninstaller did not finish within ${TimeoutSeconds}s — killing process" -ForegroundColor Red
                        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                        Write-Host "  [INFO] This program likely has a GUI uninstaller that cannot run from the terminal." -ForegroundColor Yellow
                        Write-Host "  [INFO] Please uninstall '$($entries.DisplayName)' manually:" -ForegroundColor Yellow
                        Write-Host "         Settings > Apps > Installed apps (Windows 11)" -ForegroundColor Yellow
                        Write-Host "         Control Panel > Programs and Features (Windows 10)" -ForegroundColor Yellow
                        $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='Timeout-ManualRequired'; Method='Native' }
                        continue
                    }

                    # Verify removal
                    $stillExists = Find-SoftwareEntry $entries.DisplayName
                    if (-not $stillExists) {
                        Write-Host "  [OK] Uninstalled successfully" -ForegroundColor Green
                        $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='Uninstalled'; Method='Native' }
                    } else {
                        Write-Host "  [WARN] Uninstaller ran but registry entry still exists — may need reboot or manual cleanup" -ForegroundColor Yellow
                        $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='MayNeedReboot'; Method='Native' }
                    }
                } catch {
                    Write-Host "  [FAIL] Uninstall error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "  [INFO] Please uninstall '$($entries.DisplayName)' manually via Settings > Apps" -ForegroundColor Yellow
                    $results += [PSCustomObject]@{ Name=$entries.DisplayName; Status='Error'; Method='Native' }
                }
            }
        }

        # Summary
        Write-Host "`n─── Uninstall Summary ───" -ForegroundColor Cyan
        $results | Format-Table -AutoSize

        # Post-summary advice
        $failedOrTimeout = $results | Where-Object { $_.Status -match 'Timeout|Error|NoUninstaller|ManualRequired' }
        if ($failedOrTimeout) {
            Write-Host "Some programs could not be uninstalled from the terminal." -ForegroundColor Yellow
            Write-Host "Please uninstall them manually, then run:" -ForegroundColor Yellow
            Write-Host "  .\uninstall-software.ps1 -Action Cleanup -CleanupTarget 'Name1','Name2'" -ForegroundColor White
            Write-Host "to clean up any leftovers.`n" -ForegroundColor Yellow
        }
    }

    'Cleanup' {
        if (-not $CleanupTarget -or $CleanupTarget.Count -eq 0) {
            Write-Error "Cleanup action requires the -CleanupTarget parameter."
            exit 1
        }

        Write-Host "`n─── Scanning for leftovers ───" -ForegroundColor Cyan

        foreach ($target in $CleanupTarget) {
            Write-Host "`nTarget: $target" -ForegroundColor Yellow

            $findings = @()

            # 1. Orphaned registry entries
            Write-Host "  Checking registry..." -ForegroundColor Gray
            $regEntries = $regPaths | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
                Where-Object { $_.DisplayName -and $_.DisplayName -like "*$target*" }
            foreach ($r in $regEntries) {
                $findings += [PSCustomObject]@{
                    Type     = 'Registry'
                    Path     = $r.PSPath -replace 'Microsoft\.PowerShell\.Core\\Registry::', ''
                    Detail   = "Uninstall entry: $($r.DisplayName)"
                    Action   = 'Remove registry key'
                    Command  = "Remove-Item -Path '$($r.PSPath)' -Recurse -Force"
                }
            }

            # 2. Orphaned services
            Write-Host "  Checking services..." -ForegroundColor Gray
            $services = Get-CimInstance Win32_Service | Where-Object {
                $_.DisplayName -like "*$target*" -or
                $_.Name -like "*$target*" -or
                ($_.PathName -and $_.PathName -like "*$target*")
            }
            foreach ($s in $services) {
                $exePath = $null
                if ($s.PathName) {
                    $p = $s.PathName.Trim()
                    if ($p.StartsWith('"')) {
                        $end = $p.IndexOf('"', 1)
                        if ($end -gt 0) { $exePath = $p.Substring(1, $end - 1) }
                    } elseif ($p -match '^(.+\.exe)\b') {
                        $exePath = $Matches[1]
                    }
                }
                $fileGone = $exePath -and -not (Test-Path $exePath -ErrorAction SilentlyContinue)

                $findings += [PSCustomObject]@{
                    Type     = 'Service'
                    Path     = $s.Name
                    Detail   = "$($s.DisplayName) [State: $($s.State)]$(if($fileGone){' (EXE missing!)'})"
                    Action   = 'Stop and delete service'
                    Command  = "sc.exe stop `"$($s.Name)`"; sc.exe delete `"$($s.Name)`""
                }
            }

            # 3. Orphaned scheduled tasks
            Write-Host "  Checking scheduled tasks..." -ForegroundColor Gray
            $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
                $_.TaskName -like "*$target*" -or
                $_.TaskPath -like "*$target*" -or
                (($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' ') -like "*$target*"
            }
            foreach ($t in $tasks) {
                $findings += [PSCustomObject]@{
                    Type     = 'ScheduledTask'
                    Path     = "$($t.TaskPath)$($t.TaskName)"
                    Detail   = "State: $($t.State)"
                    Action   = 'Unregister task'
                    Command  = "Unregister-ScheduledTask -TaskName '$($t.TaskName)' -TaskPath '$($t.TaskPath)' -Confirm:`$false"
                }
            }

            # 4. Orphaned startup items
            Write-Host "  Checking startup items..." -ForegroundColor Gray
            $runKeys = @(
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunDisabled'
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunDisabled'
            )
            $excludeProps = '^PS(Path|ParentPath|ChildName|Provider|Drive)$'
            foreach ($key in $runKeys) {
                if (-not (Test-Path $key)) { continue }
                $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
                if (-not $props) { continue }
                $props.PSObject.Properties |
                    Where-Object { $_.Name -notmatch $excludeProps -and ($_.Name -like "*$target*" -or $_.Value -like "*$target*") } |
                    ForEach-Object {
                        $findings += [PSCustomObject]@{
                            Type     = 'StartupItem'
                            Path     = "$key\$($_.Name)"
                            Detail   = $_.Value
                            Action   = 'Remove registry value'
                            Command  = "Remove-ItemProperty -Path '$key' -Name '$($_.Name)' -Force"
                        }
                    }
            }

            # 5. Leftover directories
            Write-Host "  Checking filesystem..." -ForegroundColor Gray
            $dirPaths = @(
                "$env:ProgramFiles"
                "${env:ProgramFiles(x86)}"
                "$env:ProgramData"
                "$env:LOCALAPPDATA"
                "$env:APPDATA"
                "$env:LOCALAPPDATA\Programs"
            )
            foreach ($base in $dirPaths) {
                if (-not (Test-Path $base)) { continue }
                Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$target*" } |
                    ForEach-Object {
                        $sizeBytes = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                                      Measure-Object -Property Length -Sum).Sum
                        $sizeMB = [math]::Round($sizeBytes / 1MB, 1)
                        $findings += [PSCustomObject]@{
                            Type     = 'Directory'
                            Path     = $_.FullName
                            Detail   = "${sizeMB} MB"
                            Action   = 'Delete directory'
                            Command  = "Remove-Item -Path '$($_.FullName)' -Recurse -Force"
                        }
                    }
            }

            # 6. Leftover TEMP files
            Write-Host "  Checking TEMP folders..." -ForegroundColor Gray
            $tempPaths = @($env:TEMP, "$env:SystemRoot\Temp")
            foreach ($tmp in $tempPaths) {
                if (-not (Test-Path $tmp)) { continue }
                Get-ChildItem $tmp -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$target*" } |
                    ForEach-Object {
                        $findings += [PSCustomObject]@{
                            Type     = 'TempDir'
                            Path     = $_.FullName
                            Detail   = 'Temporary files'
                            Action   = 'Delete directory'
                            Command  = "Remove-Item -Path '$($_.FullName)' -Recurse -Force"
                        }
                    }
            }

            # Report
            if ($findings.Count -eq 0) {
                Write-Host "  [CLEAN] No leftovers found for '$target'" -ForegroundColor Green
            } else {
                Write-Host "`n  Found $($findings.Count) leftover(s):" -ForegroundColor Yellow
                $findings | Format-Table -Property @(
                    @{N='#'; E={[array]::IndexOf($findings, $_) + 1}; W=3},
                    'Type',
                    @{N='Path'; E={if($_.Path.Length -gt 60){$_.Path.Substring(0,57)+'...'}else{$_.Path}}},
                    'Detail',
                    'Action'
                ) -AutoSize -Wrap

                Write-Host "`n  Cleanup commands (AI should present these for user confirmation):" -ForegroundColor Cyan
                $i = 0
                foreach ($f in $findings) {
                    $i++
                    Write-Host "    # $i. $($f.Type): $($f.Path)" -ForegroundColor DarkGray
                    Write-Host "    $($f.Command)" -ForegroundColor White
                }
            }
        }
    }
}
