<!--
#######################################
Author: Electric Bluefish Productions Inc.  - James Applebaum
Created: Jan 13 2016
Project: CNC-control-pendent-Kiosk-Mode-for-Surface-Pro3
File: README.md
Description: Project README for kiosk setup and decision tree.

#######################################
-->

# Windows Kiosk Setup with On-Screen Keyboard (Surface Pro3 / Touch)

This Manual Process Actually Works!

## ✅ Recommended Kiosk Model (IMPORTANT)

There are **two ways** to do kiosks on Windows:

| Method                                 | Keyboard works? | Recommendation |
|----------------------------------------|-----------------|----------------|
| **Assigned Access (single-app kiosk)** | ⚠️ Often broken | ❌ Avoid        |
| **Auto-login + Explorer shell**        | ✅ Reliable      | ⭐ **Use this** |

👉 **Do NOT use “Set up a kiosk” (Assigned Access)** if you need the touch keyboard.

Instead, use:
> **Auto-login kiosk user + normal Explorer desktop + fullscreen app**

This gives:

- Touch keyboard
- Admin escape
- Stable PowerShell
- Chrome / Edge compatibility

---

## STEP 1 — Create a kiosk user (standard user)

Open **PowerShell (Admin)**:

```powershell
net user kioskuser /add
net localgroup users kioskuser /add
```

(Do **not** make them admin.)

---

## STEP 2 — Enable auto-login for the kiosk user

1. Press **Win + R**
2. Run:
   ```
   netplwiz
   ```
3. Select **kioskuser**
4. Uncheck:
   > Users must enter a user name and password
5. OK → enter password once

Reboot test:

- Machine logs directly into kioskuser

---

## STEP 3 — Force the on-screen keyboard to work

### 3.1 Enable Touch Keyboard service

Open **PowerShell (Admin)**:

```powershell
Set-Service -Name TabletInputService -StartupType Automatic
Start-Service TabletInputService
```

This service is **required** for auto-popup keyboard.

---

### 3.2 Enable keyboard auto-show (registry)

Run as **Admin**:

```powershell
reg add "HKCU\\Software\\Microsoft\\TabletTip\\1.7" ^
/v EnableDesktopModeAutoInvoke ^
/t REG_DWORD /d 1 /f
```

⚠️ This must be run **while logged in as the kiosk user**
(or load their registry hive manually).

---

### 3.3 Optional: ensure keyboard shows in tablet mode

**Settings → Devices → Typing**
Enable:

- ✅ Show the touch keyboard when there’s no keyboard attached

---

## STEP 4 — Launch the kiosk app automatically (fullscreen)

### Example: Chromium Edge kiosk launch

Create a shortcut in:

```
C:\\Users\\kioskuser\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup
```

Target:

```text
"C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
--kiosk https://laser.applebaum.treehouse/tablet
--edge-kiosk-type=fullscreen
```

Edge:

- Triggers touch keyboard correctly
- Works better than Chrome in kiosks

---

## STEP 5 — Add a manual keyboard fallback (IMPORTANT)

Even with everything correct, **Windows touch keyboards can fail**.

Add a **visible keyboard button**.

### Pin Touch Keyboard executable

Target:

```text
C:\\Program Files\\Common Files\\microsoft shared\\ink\\TabTip.exe
```

Pin it to:

- Taskbar
- Or Desktop

This guarantees keyboard access.

---

## STEP 6 — Admin escape hatch (DO THIS)

Make sure you can **exit kiosk mode**:

- **Ctrl + Alt + Del** → Sign out
- Log in as **admin**
- Or Task Manager → Run → `explorer.exe`

Never remove Explorer shell unless you enjoy recovery installs.

---

## ✅ Resulting behavior

✔ Auto-login  
✔ Fullscreen kiosk app  
✔ Touch keyboard auto-pops  
✔ Manual keyboard fallback  
✔ Admin can escape safely  
✔ No Assigned Access traps

---

## ❌ What NOT to do

- ❌ Windows “Set up a kiosk”
- ❌ Assigned Access + Chrome
- ❌ Shell replacement
- ❌ Disabling Explorer
- ❌ Removing admin access

---

## Quick verification checklist

Log in as kiosk user and test:

```powershell
services.msc
```

Confirm:

- `TabletInputService` = **Running**

Tap a text field:

- Keyboard appears → success
  """

path = "/mnt/data/README.md"
with open(path, "w", encoding="utf-8") as f:
f.write(content)

path
___
############################################################################################
___

# Microsoft Surface Pro (kiosk) for CNC pendent — setup scripts & decision tree

**There are aspects of this that did work, but others that were frustrating or just did not accomplish the task.**
Note: this document documents the kiosk setup for the Surface device attached to the laser table. The instructions target a Windows Surface device the kiosk steps apply to Surface Pro 3+ devices running Windows 10/11. If your device or Windows version differs, see the decision tree below.

---

## Summary / Intent
- Goal: Lock the Surface into a single-app kiosk for CNC table control.
- Behaviour: auto-login to a local kiosk account, launch a browser in fullscreen kiosk mode, block access to desktop and other apps, keep the device quarantined from the internet.

## Important security note (network quarantine)
This Surface **can be** intentionally **quarantined from the Internet** because the control machine runs an older Windows build and must be isolated from external threats.

```
[root@server root]# firewall-cmd --direct --get-all-rules
- ipv4 filter FORWARD 0  -i enp[0] -o eno[1] -j ACCEPT
- ipv4 filter FORWARD 0  -i eno[1] -o enp[0] -m state --state RELATED,ESTABLISHED -j ACCEPT
- ipv4 filter FORWARD -1 -s 192.168.[#].[#] -o eno1 -j DROP
```

Evaluation order (most-specific/drop first):
1. FORWARD -1 -s 192.168.100.[#] -o eno1 -j DROP
2. FORWARD 0 -i enp5s0 -o eno1 -j ACCEPT
3. FORWARD 0 -i eno1 -o enp5s0 -m state --state RELATED,ESTABLISHED -j ACCEPT

---

## Quick required outcomes
- Local kiosk account with no password.
- Device auto-signs into kiosk account on boot (optional — use only if physically secure).
- Browser starts automatically in fullscreen kiosk mode to a single URL.
- Touch keyboard and browser behaviour verified (Edge vs Chrome differences noted below).

---

## New: `scripts/edit-kiosk-config.ps1` — interactive config editor

A new helper script was added to simplify creating and editing your local `scripts/kiosk.config.json`.

Purpose:

- Create or update `scripts/kiosk.config.json` from the provided sample (`scripts/kiosk.config.sample.json`) or defaults.
- Avoid committing secrets: the script reminds you to use `scripts/generate-kiosk-pwd.ps1` to create an encrypted `scripts/kiosk.pwd` if you need a password.

Usage (interactive):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\edit-kiosk-config.ps1
```

Non-interactive (advanced):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\edit-kiosk-config.ps1 -OutFile .\scripts\kiosk.config.json -NonInteractive -KioskUserName MyKiosk -KioskUrl https://example.local -Browser Edge -EnableAutoLogin $true
```

Notes:

- The script defaults to recommending a no-password kiosk account. If you want a password, use `scripts/generate-kiosk-pwd.ps1` to generate `scripts/kiosk.pwd` (DPAPI-encrypted) and set
  `EncryptedPasswordFile` in your config.
- Do NOT commit `scripts/kiosk.config.json` or `scripts/kiosk.pwd` — they are added to `.gitignore` by default.

---

## Step-by-step (concise)

1) Create a local kiosk user (no password) — 5 minutes
- Settings → Accounts → Other users → Add account → I don’t have this person’s sign-in information → Add a user without a Microsoft account
- Pick a short name (e.g. "laser" or "GuestKiosk"). Leave password blank.

2) Windows version and browser compatibility check — 5 minutes
- Run `winver` and confirm Windows build. Older builds (e.g., 1511) have known browser/input issues.
- Recommended: update to latest Windows 10/11 feature update (22H2 or later) if possible.

3) (If needed) Run Update Assistant — 30–90 minutes depending on download & install
- Download and run the Windows 10/11 Update Assistant from Microsoft.
- Reboot as requested.

4) Install modern Chromium Edge (recommended) — 10–20 minutes
- Chromium Edge tends to integrate with the Windows touch keyboard and text services better than Chrome for certain Surface scenarios.

5) Enable Assigned Access (Assigned Access / Kiosk mode) — 5–10 minutes
- Admin account → Settings → Accounts → Family & other users → Set up a kiosk → Get started → Choose the kiosk user → Choose the app (Google Chrome or Microsoft Edge) → Provide the kiosk URL and choose fullscreen/kiosk-mode.

6) Auto sign-in (optional) — 2 minutes
- Run `Win + R` → `netplwiz` → Select kiosk user → Uncheck “Users must enter a user name and password” → Leave password blank.
- Only use if the device is physically secure.

7) Harden Chrome/Edge kiosk flags (optional) — 5 minutes
- Create or edit the kiosk app shortcut to add flags. Example for Chrome:

```
chrome.exe --kiosk https://yourwebsite.com --no-first-run --disable-translate --disable-infobars
```

- Example for Edge (Chromium):

```
msedge.exe --kiosk https://yourwebsite.com --kiosk-type=fullscreen --no-first-run
```

8) Test & validate — 10–30 minutes
- Reboot the device, verify auto-login, correct URL loads, touch input works, on-screen keyboard behavior OK, and no access to desktop or other apps.

---

## Known Windows + Browser + Touch-keyboard behaviour
- Chrome does not always trigger the Windows touch keyboard because it treats touch as pointer input and does not always call TabTip.exe.
- Microsoft Edge (Chromium) hooks into Windows Text Services and more reliably triggers the on-screen keyboard.
- If your web app requires the on-screen keyboard and Chrome does not open it reliably, prefer Edge or update Chrome + Windows and test.

If you must use Chrome and have touch input problems, possible mitigations:
- Ensure Windows is updated to a modern feature update.
- Install Chromium Edge and test; change the Assigned Access app to Edge if it behaves better.
- Consider a small on-screen JavaScript keyboard inside your web app as a fallback (last-resort).



### OS upgrade decision tree (quick)
This decision tree helps you choose the next action and shows an expected completion time range.

1) What Windows build is installed? (run `winver`)
   - If build < 19041 (older than ~Windows 10 2004):
     - Action: Run Windows Update Assistant → 30–90 min
     - Then: Install Chromium Edge → 10–20 min
   - If build >= 19041 and you have Edge Chromium or latest Chrome:
     - Action: Proceed to Assigned Access → 5–10 min

2) Do you need the on-screen touch keyboard to appear reliably in the browser?
   - Yes:
     - Preferred: Use Edge (Chromium) in Assigned Access → 5–10 min to switch/test
     - Alternate: Use Chrome but plan for touch-keyboard fallbacks / in-app keyboard → 30–120 min development/testing
   - No: Chrome in Assigned Access is acceptable.

3) Is the device physically secured (allowed auto-login)?
   - Yes: enable auto sign-in via `netplwiz` → 2 min
   - No: do NOT enable auto sign-in — require manual login.

4) install Powershell 7.x
   👉 https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows

Estimated total time (happy path): 20–45 minutes (create user, assign access, test). If updates or browser install required: 1–2 hours.

---

## Useful commands & links
- Windows Update Assistant: https://support.microsoft.com/en-us/topic/windows-update-assistant-3550dfb2-a015-7765-12ea-fba2ac36fb3f
- Example `netplwiz` quick steps: Win + R → `netplwiz` → select user → uncheck password requirement.
- Chrome kiosk flags example:

```
chrome.exe --kiosk https://yourwebsite.com --no-first-run --disable-translate --disable-infobars
```

- Edge kiosk flags example:

```
msedge.exe --kiosk https://yourwebsite.com --kiosk-type=fullscreen --no-first-run
```

---

# Kiosk setup helper (PowerShell)

This repository contains a configurable PowerShell helper script to create a local kiosk user, enable optional auto-login, install Edge (via winget), and register a scheduled task that launches the browser in kiosk mode.

What's new

- Default behavior: the script now prefers a local `scripts/kiosk.config.json` by default (new parameter `-PreferConfig` is `true` by default). This makes the config file the canonical source of truth
  for installs; to let CLI parameters override the config, run with `-PreferConfig:$false`.
- `-DisableAutoLogin` opt-out now requires explicit confirmation from the CLI (`-Yes`) to prevent accidental insecure changes.
- `scripts/generate-kiosk-pwd.ps1` helper added: interactively creates a DPAPI-encrypted `scripts/kiosk.pwd` file when you explicitly choose to provide a password. Default behaviour is to NOT create a password file (recommended).
- Tests: `tests/Setup-Kiosk.Tests.ps1` now gracefully skips when Pester is not installed and includes a non-interactive test that verifies `generate-kiosk-pwd.ps1` writes a password file when supplied a SecureString.

Files of interest
- `scripts/setup-kiosk.ps1` — main script (run as Administrator).
- `scripts/generate-kiosk-pwd.ps1` — helper to create `scripts/kiosk.pwd` safely (interactive default: no password).
- `scripts/kiosk.config.sample.json` — sanitized sample configuration (safe to commit).
- `scripts/kiosk.config.json` — local configuration (DO NOT commit; add to `.gitignore`).
- `scripts/kiosk.pwd` — optional encrypted password file produced with `ConvertFrom-SecureString` (DO NOT commit).
- `tests/Setup-Kiosk.Tests.ps1` — Pester tests (skip if Pester missing; includes a test that creates a temporary password file non-interactively).

Configuration
- Copy `scripts/kiosk.config.sample.json` -> `scripts/kiosk.config.json` and fill values.
- Important config keys (sample):
  - `KioskUserName`, `KioskFullName`, `KioskUrl`, `Browser` (`Edge`/`Chrome`), `EnableAutoLogin` (bool), `MinimumBuild` (int), `InstallEdgeIfMissing` (bool)
  - `DisableAutoLogin` (bool) — opt-out flag. Auto-login is enabled by default when `EnableAutoLogin` is true; set `DisableAutoLogin: true` in config or pass `-DisableAutoLogin` on the CLI to prevent AutoAdminLogon from being configured.
  - Backwards compatibility: if an older config contains `ConfirmAutoLogin`, the script will treat it as the inverse (i.e., `DisableAutoLogin = -not ConfirmAutoLogin`) so older configs continue to work.
  - `EncryptedPasswordFile` — file name for optional encrypted password (default `kiosk.pwd`).

Security guidance (short)
- Default recommendation: use a no-password kiosk account. The helper `generate-kiosk-pwd.ps1` defaults to not creating a password file so you must explicitly opt in.
- If you supply a password, `setup-kiosk.ps1` will write the password into the registry (AutoAdminLogon requires plaintext). This is a Windows limitation.
- DPAPI-encrypted `kiosk.pwd` can only be decrypted by the same Windows account that encrypted it. Create `kiosk.pwd` using the same Windows user that will run the installer script on the target machine.

How to create an encrypted password file (interactive — recommended only if you need a passworded kiosk account)

Run as the Windows user who will run the installer (do NOT run as a different administrator account if you want the file usable by a non-elevated installer account):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\generate-kiosk-pwd.ps1
# Follow prompts; the script defaults to NOT creating a password unless you explicitly choose to.
```

Non-interactive (advanced and less secure) — example only:

```powershell
# Avoid passing plaintext passwords in real automation. This is an advanced example.
$secure = ConvertTo-SecureString 'StrongPass123!' -AsPlainText -Force
pwsh -ExecutionPolicy Bypass -File .\scripts\generate-kiosk-pwd.ps1 -OutFile .\scripts\kiosk.pwd -PasswordSecureString $secure -Force
```

Usage examples (config-first behavior)

- Dry-run to review changes using the local config (recommended):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1 -WhatIf
```

- Real install using the created local config (run this in an elevated PowerShell — "Run as Administrator"):

```powershell
# Open an elevated shell first, then run:
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1
```

- Attempt install and have the script install Edge if missing (elevated):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1 -InstallEdgeIfMissing
```

- Explicitly disable auto-login from the CLI (requires confirmation flag -Yes):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1 -DisableAutoLogin -Yes
```

- Force CLI parameters to override the config (previous behavior):

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1 -PreferConfig:$false -KioskUserName GuestKiosk -KioskUrl "https://example.local" -Browser Edge -WhatIf
```

- Provide an explicit browser executable path if automatic detection misses your msedge.exe:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1 -BrowserPath "C:\Program Files\Microsoft\Edge\Application\msedge.exe" -WhatIf
```

Pester tests
- Tests are intentionally safe and conservative:
  - They skip entirely (exit 0) if Pester is not available on the runner, so CI doesn't fail a non-Windows host accidentally.
  - Tests include a non-interactive test that calls `generate-kiosk-pwd.ps1` with a SecureString to assert that a password file is created.

Run tests (on Windows with pwsh + Pester):

```powershell
Install-Module -Name Pester -Scope CurrentUser -Force
pwsh -NoProfile -Command "Invoke-Pester -Script .\tests\Setup-Kiosk.Tests.ps1"
```

.gitignore
- The repo `.gitignore` includes:
  - `scripts/kiosk.config.json`
  - `scripts/kiosk.pwd`

Decision tree (condensed)
- Prep (2–5 min): confirm elevated PowerShell.
- Check Windows build (2 min): if too old, upgrade (20–60+ min).
- Create kiosk user (1–5 min).
- Browser availability (3–15 min if installing via winget, otherwise manual install 5–20 min).
- Auto-login config (1–2 min) — enabled by default when `EnableAutoLogin` is true; pass `-DisableAutoLogin` to opt out.
- Scheduled task registration (1–3 min).
- Reboot & validate (5–10 min).

Support / next steps
- I can add a GitHub Actions workflow that runs Pester tests on `windows-latest` and installs Pester if needed. I can also add a stricter interactive confirmation for AutoAdminLogon. Which would you prefer?

Changelog
- Default behavior changed: Auto-login is enabled by default when `EnableAutoLogin` is true; added `-DisableAutoLogin` opt-out in `setup-kiosk.ps1`.
- Added `scripts/generate-kiosk-pwd.ps1` helper that defaults to not creating a password file.
- Updated tests to skip when Pester missing and added a non-interactive helper test.
# CNC-control-pendent-Kiosk-Mode-for-Surface-Pro3
