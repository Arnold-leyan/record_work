# AI Agent Installation Guide

This file is for AI agents that need to install, configure, verify, or use the `record_work` automation.

The human-facing project overview is in `README.md`. Do not rely on the old encoded text from previous versions of this file.

## Objective

Install and prepare the work-log automation so an AI agent can record a daily work log by running one command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\run.ps1" -Content "<work-log-content>"
```

The automation handles VPN, internal-system login, quick check-in, note editing, saving, and VPN cleanup.

## Operating Rules For Agents

1. Prefer executing commands over asking the user to do manual setup.
2. Ask the user only for secrets or private values that are missing from `.env`.
3. Never print full passwords, VPN secrets, or private certificate pins in the final response.
4. Do not copy `.env` into public locations.
5. Do not reimplement the browser workflow. Use `run.ps1`.
6. Do not ask the user to manually use the internal website unless the automation fails after setup and VPN checks.

## Required Environment

The project is intended for Windows.

Required tools:

- PowerShell 5.1 or newer.
- Node.js LTS.
- `node` available in `PATH`.
- `npm.cmd` available in `PATH`.

Required project files:

- `setup.ps1`
- `vpn-connect.ps1`
- `.env.example`
- `.agents\skills\work-log\run.ps1`
- `.agents\skills\work-log\work-log.js`
- `.agents\skills\work-log\package.json`
- `vpn-installer\bin\openconnect.exe`
- one root-level file matching `*VPN*.bat`

## Quick Install

Run from the repository root:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1"
```

Expected behavior:

- validates Node.js and npm;
- creates `.env` from `.env.example` if missing;
- validates required `.env` keys;
- installs npm dependencies in `.agents\skills\work-log`;
- installs Playwright Chromium;
- prints a test command when complete.

If the command exits with code `2` because `.env` is incomplete, collect the missing values from the user, update `.env`, then rerun setup.

## Automated Preflight

Before running setup, an agent may inspect the workspace:

```powershell
Get-ChildItem -Force
Test-Path -LiteralPath ".\setup.ps1"
Test-Path -LiteralPath ".\.agents\skills\work-log\run.ps1"
Test-Path -LiteralPath ".\vpn-installer\bin\openconnect.exe"
Get-ChildItem -LiteralPath "." -Filter "*VPN*.bat" -File
```

If these files are missing, report the missing file list and stop.

## `.env` Handling

The setup script creates `.env` automatically if it does not exist. Required keys are:

```text
account
password
VPN_account
VPN_password
VPN_gateway
VPN_cert
internal_ip
department
```

Recommended optional key:

```text
customer_name
```

If values are missing, ask the user for a plain `key=value` block. Ask only for missing keys.

Example prompt to the user:

```text
Please provide the missing private config values as key=value lines:

account=
password=
VPN_account=
VPN_password=
VPN_gateway=
VPN_cert=
internal_ip=
department=
customer_name=
```

After receiving values, write or update `.env` in the repository root, then rerun:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1"
```

Security requirements:

- Do not commit `.env`.
- Do not include secret values in summaries.
- Do not copy `.env` to external skill directories.

## Install For Repo-Local Use

The repo-local skill directory is:

```text
.agents\skills\work-log
```

After successful setup, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\.agents\skills\work-log\run.ps1" -Content "setup-test"
```

A successful run prints JSON with `"ok": true`.

## Install For Codex

Run from the repository root:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkillDir "$env:USERPROFILE\.codex\skills\work-log"
```

This copies these files into the Codex skill directory:

- `SKILL.md`
- `package.json`
- `package-lock.json`
- `run.ps1`
- `work-log.js`

It also creates:

```text
%USERPROFILE%\.codex\skills\work-log\.record-work-root
```

That file points to the real repository root, allowing the installed skill to find `.env`, VPN scripts, and bundled VPN binaries.

Use this command after installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\work-log\run.ps1" -Content "<work-log-content>"
```

## Install For Claude Code

Run from the repository root:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkillDir "$env:USERPROFILE\.claude\skills\work-log"
```

Use this command after installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\work-log\run.ps1" -Content "<work-log-content>"
```

## Sync Common External Skill Directories

If the agent should prepare all common external skill locations, run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SyncExternalSkills
```

This syncs:

- `%USERPROFILE%\.codex\skills\work-log` if `%USERPROFILE%\.codex\skills` exists.
- `%USERPROFILE%\.claude\skills\work-log` if `%USERPROFILE%\.claude\skills` exists.

## Browser Install Control

To skip Playwright Chromium installation:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkipBrowserInstall
```

Use this only when Chromium is already installed for Playwright or when network access is unavailable and browser installation will be handled later.

## Running The Work Log

Single content for both note fields:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\run.ps1" -Content "<work-log-content>"
```

Separate external and internal content:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\run.ps1" -Content "<external-note>" -Content2 "<internal-note>"
```

If `-Content2` is omitted, the script uses `-Content` for both fields.

## Expected Successful Output

The script writes status logs and then JSON similar to:

```json
{
  "ok": true,
  "staffName": "...",
  "customer": "...",
  "alreadyRegistered": false,
  "regId": "...",
  "noteId": "...",
  "department": "3",
  "contentLength": 10,
  "content2Length": 10
}
```

In the final response to the user, report:

- whether the run succeeded;
- `noteId` or `regId` when available;
- that VPN was closed if the script says it closed VPN;
- any failure reason if the command exits nonzero.

Do not include secret values.

## Troubleshooting

### `Node.js is not installed`

Install Node.js LTS or ask the user to allow an automated Node.js installation if available in the environment. Then rerun setup.

### `npm.cmd is not available`

Node.js is missing or not correctly added to `PATH`. Reinstall Node.js LTS or reopen the shell after installation.

### `.env` missing required values

Ask the user for only the missing keys as `key=value` lines. Update `.env`, then rerun setup.

### `VPN launcher not found`

A root-level `*VPN*.bat` file is missing. Check whether the repository was copied incompletely.

### `openconnect.exe not found`

Check whether `vpn-installer\bin` exists and contains `openconnect.exe`.

### `VPN did not come up within 60s`

Likely causes:

- incorrect VPN credentials;
- incorrect `VPN_gateway`;
- incorrect `VPN_cert`;
- UAC prompt was not approved;
- network cannot reach the VPN gateway.

Ask the user to confirm secrets only if needed.

### `Cannot locate record_work project root`

The skill is running outside the repository and cannot locate `.env` or VPN files. Fix with one of:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkillDir "<skill-dir>"
```

or set:

```powershell
$env:RECORD_WORK_ROOT="C:\path\to\record_work"
```

or create:

```text
<skill-dir>\.record-work-root
```

containing the real repository root path.

### Playwright install failed

Retry setup first. If only browser installation failed:

```powershell
Push-Location ".\.agents\skills\work-log"
npm install
npx playwright install chromium
Pop-Location
```

## Agent Checklist

Use this checklist when taking over a fresh clone:

1. Confirm current directory is repository root.
2. Confirm required files exist.
3. Run `setup.ps1`.
4. If `.env` is incomplete, ask user for missing secrets only.
5. Rerun `setup.ps1`.
6. Optionally sync to Codex or Claude with `-SkillDir` or `-SyncExternalSkills`.
7. Run a `setup-test` entry only if the user allows creating a real log entry.
8. For normal use, call `run.ps1 -Content "<work-log-content>"`.

