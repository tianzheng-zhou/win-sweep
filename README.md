# win-sweep

[简体中文](README.zh-CN.md) | English

**Windows sluggish again? Boot spinner going for 30 seconds? Fan screaming for no reason?**

You're not alone. Every Windows machine shares the same fate — blazing fast right after a fresh install, then a year or two later, the bloat creeps in. Install software and it sneaks in an auto-start service. Uninstall software and it leaves behind a pile of registry leftovers. Vendor telemetry runs silently in the background for hundreds of days without you knowing. By the time you've had enough and try to clean up — you open the registry editor, then quietly close it.

win-sweep is not another "one-click optimizer." It puts the expert decision-making logic of system cleanup into the AI's hands. You just talk:

```
You: My PC is booting slower and slower, take a look
AI:  [Running diagnostics] Found 47 Auto services, 12 startup items, 3 telemetry scheduled tasks...
     Suggest changing these 8 services to Manual:
     | # | Service         | Purpose        | Risk |
     | 1 | AdobeARMservice | Adobe updater  | Low  |
     | ...
     Proceed? Say "skip #3" to exclude specific items.
```

**No commands to memorize. No software to install. You keep full control.** Every change waits for your approval, and anything changed can be rolled back.

Works with any AI coding tool that has a terminal: VS Code Copilot, Claude Code, Cursor, Windsurf, Codex CLI, Gemini CLI, and more.

## What It Does

| Feature | Description | Script |
|---------|-------------|--------|
| **System Health Check** | Disk usage, memory top 30, startup items, services, scheduled tasks | `diagnose.ps1` |
| **Service Slimming** | Auto-identify safely adjustable services, batch-change to Manual/Disabled | `optimize-services.ps1` |
| **Startup Management** | Disable startup items with backup to `RunDisabled` (recoverable anytime) | `manage-startups.ps1` |
| **Telemetry Sweep** | Three-layer cross-check: services + tasks + startup items — prevent mutual re-activation | `clean-tasks.ps1` |
| **Suspicious Service Scan** | 12-signal quantified risk scoring to catch leftover/unsigned/unknown services | `detect-suspicious.ps1` |
| **Software Removal & Cleanup** | Scan installed software and recommend removals; after user uninstalls manually via Settings/Control Panel, scan 6 areas for leftovers (services, tasks, startup items, directories, registry, temp files) and clean them up. Terminal-only uninstall supported for winget/MSI packages with timeout protection | `uninstall-software.ps1` |
| **Change Verification** | Auto-verify each change took effect, compare before/after | `verify.ps1` |

### Highlights

- **Conversation-driven** — No commands to remember; describe what you need in natural language, and the AI executes
- **Framework, not a list** — Built on universal decision logic; can analyze unknown services without relying on hardcoded lists
- **Three-layer telemetry kill** — Disabling just the service is useless (scheduled tasks will re-enable it); must disable services + tasks + startup items together
- **Reversible by design** — Startup items are backed up not deleted, services default to Manual not Disabled, high-risk ops get registry export first
- **Strong uninstall** — AI diagnoses what to remove, you uninstall via Settings/Control Panel, then AI sweeps 6 types of leftovers. For winget/MSI software, terminal uninstall is available with timeout protection. Force-delete only as absolute last resort in Safe Mode
- **Zero dependencies** — Pure PowerShell 5.1, built into Windows 10/11, no third-party installs

## Quick Start

### 1. Install

win-sweep follows the [Agent Skills](https://agentskills.io/) open standard — a `SKILL.md` entry file plus a directory of supporting scripts and docs. Major AI coding tools already support it.

#### Option A: Personal Global Install (Recommended — Available Across All Projects)

Clone directly into your tool's personal skill directory. **Just pick the tool you use.**

```powershell
# ✅ Cross-tool universal path (VS Code Copilot / Windsurf / Gemini CLI / Codex CLI all recognize this)
git clone https://github.com/tianzheng-zhou/win-sweep.git "$HOME\.agents\skills\win-sweep"

# Claude Code (uses its own path; VS Code Copilot also recognizes this path)
git clone https://github.com/tianzheng-zhou/win-sweep.git "$HOME\.claude\skills\win-sweep"
```

> If you use both Claude Code and other tools, you need to **clone to both paths**.
>
> To update: `cd` into the directory and run `git pull`.

<details>
<summary>Each tool also has its own dedicated path (optional)</summary>

| Tool | Personal Skill Directory | Notes |
|------|-------------------------|-------|
| **VS Code Copilot** | `~/.copilot/skills/` | [Docs](https://code.visualstudio.com/docs/copilot/customization/agent-skills); also recognizes `~/.claude/skills/` and `~/.agents/skills/` |
| **Claude Code** | `~/.claude/skills/` | [Docs](https://code.claude.com/docs/en/skills) |
| **Windsurf** | `~/.codeium/windsurf/skills/` | [Docs](https://docs.windsurf.com/windsurf/cascade/skills); also recognizes `~/.agents/skills/` |
| **Gemini CLI** | `~/.gemini/skills/` | [Docs](https://geminicli.com/docs/cli/skills/); also recognizes `~/.agents/skills/`; supports `gemini skills link <path>` for one-command install |
| **Codex CLI** | `~/.agents/skills/` (only path) | [Docs](https://developers.openai.com/codex/skills) |

</details>

#### Option B: Project-Level Install (Current Project Only)

Clone into the project's skill directory; can be committed to version control:

```powershell
# Using .agents/skills/ as example (covers the most tools)
git clone https://github.com/tianzheng-zhou/win-sweep.git .agents/skills/win-sweep
```

Path compatibility:

| Path | Recognized By |
|------|--------------|
| `.agents/skills/win-sweep/` | VS Code Copilot, Windsurf, Gemini CLI, Codex CLI |
| `.claude/skills/win-sweep/` | Claude Code, VS Code Copilot |
| `.github/skills/win-sweep/` | VS Code Copilot |
| `.windsurf/skills/win-sweep/` | Windsurf |
| `.gemini/skills/win-sweep/` | Gemini CLI |

> Recommend `.agents/skills/` — one directory covers the most tools. If your team also uses Claude Code, add another clone to `.claude/skills/`.

#### Cursor Users

Cursor does not yet support the Agent Skills standard. Use [Rules](https://docs.cursor.com/context/rules) instead:

1. Clone win-sweep into your project directory
2. Create `.cursor/rules/win-sweep.md` referencing the SKILL.md and script paths

#### Other Tools

Place the win-sweep directory in your project and manually guide the AI to read `SKILL.md`.

### 2. Start a Conversation

Describe your problem to the AI:

```
> Run a system health check
> Are there any auto-start services I can turn off?
> Scan for telemetry components and disable them all
> Check for suspicious leftover services
> Uninstall Adobe Flash and clean up all its leftovers
> Help me remove bloatware I don't need
> My C: drive is almost full, see what's taking up space
```

The AI will invoke the appropriate script, analyze results, and present recommendations for your approval.

### 3. Administrator Privileges

Admin privileges affect **both diagnosis and modification**.

**Without admin, diagnostic results are incomplete** — service binary paths, HKLM startup items, scheduled task details, and signature checks may be missing or inaccurate. The AI will proactively warn you about what's missing.

**Method: Launch your AI tool as Administrator — internal commands automatically inherit the privileges.**

| Tool | How to Elevate |
|------|---------------|
| VS Code / Cursor / Windsurf | Right-click the app icon → Run as administrator |
| Terminal-based (Claude Code / Codex CLI / Gemini CLI, etc.) | Open an admin terminal first, then launch the tool |

> Works without elevation too — the AI will warn you about incomplete results and let you decide whether to proceed.

<details>
<summary>Permission requirements by operation</summary>

| Operation | Needs Admin | What's Missing Without Admin |
|-----------|------------|-----------------------------|
| System diagnostics | **Recommended** | Service binary paths, startup accounts, some process details incomplete |
| Service optimization | Yes | Will fail |
| HKCU startup items | No | — |
| HKLM startup items | Yes | Cannot read or modify |
| Scheduled task cleanup | Yes | Will fail |
| Software uninstall | Partial (HKCU apps no; HKLM apps yes) | System-level apps cannot be uninstalled |
| Software leftover cleanup | Yes | Cannot clean services, HKLM registry, Program Files |
| Suspicious service detection | Yes | Signature checks and service details incomplete |
| Change verification | Partial | Some checks will be skipped |

</details>

## Safety Design

**You always have the final say.** Every modification is executed only after your confirmation.

| Risk Level | Example | Confirmation |
|------------|---------|-------------|
| Read-only | Diagnostic scans | Runs directly, no prompt |
| Low-risk | Service Auto → Manual | Summary table, one-time confirm; can exclude items |
| Medium-risk | Service → Disabled, disable scheduled tasks | Summary confirm + impact description |
| High-risk | Delete service/registry keys | **Backup first** → per-item confirm → rollback command provided |

Additional safeguards:

- Suggests creating a **system restore point** before first modification
- Logs **timestamp + original value → new value + command executed** for each change (audit trail)
- Startup item "disable" actually moves to the `RunDisabled` key as backup — one command to restore

## Project Structure

```
win-sweep/
├── SKILL.md                    # Skill entry point (AI reads this for instructions)
├── scripts/                    # PowerShell tool scripts
│   ├── diagnose.ps1            # System diagnostics (read-only)
│   ├── optimize-services.ps1   # Batch service startup mode adjustment
│   ├── manage-startups.ps1     # Startup item disable/restore
│   ├── clean-tasks.ps1         # Scheduled task scan & disable
│   ├── detect-suspicious.ps1   # Suspicious service risk scoring
│   ├── uninstall-software.ps1  # Software uninstall & leftover cleanup
│   └── verify.ps1              # Change verification & before/after comparison
└── references/                 # AI reference docs (loaded on demand)
    ├── service-rules.md        # Service decision framework
    ├── telemetry.md            # Telemetry identification & three-layer disable
    ├── suspicious-checklist.md # 12-signal risk scoring system
    ├── uninstall-guide.md      # Software removal decision framework & leftover cleanup
    └── sc-gotchas.md           # sc.exe / PowerShell common gotchas
```

## Requirements

- Windows 10 / 11
- PowerShell 5.1+ (built into Windows)
- No third-party dependencies

## Disclaimer

> This tool uses AI to assist in modifying Windows system configuration. While it includes tiered safety mechanisms, **modifying system configuration carries inherent risk**. You are responsible for deciding whether to accept each change. The author assumes no liability for any damage caused by use of this tool. Creating a system restore point before use is recommended.

## License

[MIT](LICENSE)
