# Microsoft 365 sign-in cleanup for RedCedar / EagleTG

Use this repo when Teams, OneDrive, Outlook, or Office keeps using the wrong RedCedar/EagleTG tenant, stale account, or stale Teams contact.

There are four scripts:

- `Clear-TeamsCache.ps1`: light cleanup for Teams cache and stale Teams search/chat identity issues.
- `Clear-NewOutlookAccounts.ps1`: cleanup for New Outlook account/app state and stale Outlook sign-in choices.
- `Clear-ClassicOutlookProfiles.ps1`: cleanup for classic Outlook mail profiles with dated OST/NST backups.
- `Clear-WorkAccountsAndReboot.ps1`: broader Microsoft 365 sign-in cleanup for RedCedar/EagleTG tenant login problems, followed by a reboot.

## Table of contents

- [Which script should I use?](#which-script-should-i-use)
- [Option 1: clear Teams cache only](#option-1-clear-teams-cache-only)
- [Option 2: clear New Outlook accounts only](#option-2-clear-new-outlook-accounts-only)
- [Option 3: clear classic Outlook mail profiles only](#option-3-clear-classic-outlook-mail-profiles-only)
- [Option 4: clear RedCedar/EagleTG Microsoft 365 sign-in state and reboot](#option-4-clear-redcedareagletg-microsoft-365-sign-in-state-and-reboot)
- [Before you run a script](#before-you-run-a-script)
- [What each script changes](#what-each-script-changes)
- [What these scripts do not change](#what-these-scripts-do-not-change)
- [More details](#more-details)
- [Review a script before running](#review-a-script-before-running)

## Which script should I use?

### Use `Clear-TeamsCache.ps1` when

- Teams search or chat keeps showing an old person/contact.
- A 1:1 or group chat points to an old guest identity.
- Teams still shows stale results after the tenant guest account was fixed.
- You only want to close Teams, clear Teams cache, and reopen Teams.

Start here for stale Teams contact issues.

### Use `Clear-NewOutlookAccounts.ps1` when

- New Outlook keeps showing stale accounts or mailbox choices.
- New Outlook keeps returning to the wrong tenant after account changes.
- You only want to close New Outlook, clear New Outlook app/account state, and reopen New Outlook.

This script does not clear classic Outlook mail profiles.

### Use `Clear-ClassicOutlookProfiles.ps1` when

- Classic Outlook keeps opening the wrong mailbox/profile.
- You need to remove classic Outlook MAPI profiles and force a fresh profile setup.
- You want to move OST/NST cache files into a dated backup folder before profile removal.

This script does not clear New Outlook app state.

### Use `Clear-WorkAccountsAndReboot.ps1` when

- Teams, OneDrive, Outlook, or Office keeps signing into the wrong tenant.
- Microsoft 365 apps keep showing old RedCedar/EagleTG sign-in errors.
- OneDrive or Office is stuck on stale work/school authentication.
- The Teams-only cleanup did not fix the issue.

This script is stronger. It closes Microsoft 365 apps, clears selected sign-in state, installs Company Portal when available, and reboots the computer.

## Option 1: clear Teams cache only

### Recommended command

Download the script, review it if needed, then run it:

```powershell
$Script = "$env:TEMP\Clear-TeamsCache.ps1"
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-TeamsCache.ps1?$(Get-Date -Format yyyyMMddHHmmss)" -OutFile $Script
Get-Content $Script
& $Script
```

This avoids piping downloaded code directly into PowerShell.

The script:

1. Stops Teams.
2. Clears New Teams and Classic Teams cache folders.
3. Relaunches Teams.

After Teams opens, start a **new** chat and type the full email address. Do not reuse an old chat thread that was bound to an old identity.

### If Teams still shows stale account choices

```powershell
$Script = "$env:TEMP\Clear-TeamsCache.ps1"
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-TeamsCache.ps1?$(Get-Date -Format yyyyMMddHHmmss)" -OutFile $Script
& $Script -IncludeIdentityCache
```

`-IncludeIdentityCache` also clears local Microsoft account-picker/token broker cache folders. This can sign Teams or other Microsoft apps out for the current Windows user.

### Clear Teams cache without reopening Teams

```powershell
$Script = "$env:TEMP\Clear-TeamsCache.ps1"
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-TeamsCache.ps1?$(Get-Date -Format yyyyMMddHHmmss)" -OutFile $Script
& $Script -NoLaunch
```

## Option 2: clear New Outlook accounts only

### Recommended command

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-NewOutlookAccounts.ps1?$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

The script:

1. Stops New Outlook.
2. Resets the New Outlook app package when Windows supports `Reset-AppxPackage`.
3. Clears New Outlook for Windows package app data for the current Windows user.
4. Clears local Microsoft account-picker/token broker cache folders.
5. Leaves New Outlook closed so users can open classic Outlook instead.

New Outlook does not use classic Outlook MAPI mail profiles. This cleanup resets local New Outlook app/account state, but it does not delete mail from Microsoft 365.

Clearing Microsoft identity caches can sign Outlook, Teams, Office, OneDrive, or other Microsoft apps out for the current Windows user.


## Option 3: clear classic Outlook mail profiles only

### Recommended command

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-ClassicOutlookProfiles.ps1?$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

The script:

1. Stops classic Outlook.
2. Creates a dated backup folder under `%LocalAppData%\Microsoft\Outlook\Backups`.
3. Exports classic Outlook profile/settings registry keys to the backup folder.
4. Moves local `*.ost` and `*.nst` cache files into the backup folder.
5. Moves `RoamCache` into the backup folder.
6. Removes classic Outlook mail profile registry keys and `DefaultProfile` values.
7. Leaves Outlook closed so users can open classic Outlook and create/sign into a fresh profile.

The script does not move PST files. PST files may contain local-only archive data and should be handled manually.

## Option 4: clear RedCedar/EagleTG Microsoft 365 sign-in state and reboot

### RedCedar / RCTG users

Most RedCedar users should use this:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

### EagleTG / ETG users

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ETG
```

### If you use both RedCedar and EagleTG

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant Both
```

### Last resort: clear all Microsoft 365 logins

Use this only if the commands above do not fix the problem:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ALL
```

`-Tenant ALL` may sign you out of other Microsoft 365 tenants or organizations on this Windows profile.
It also resets Office sign-in/licensing state, signs out Office WAM accounts, clears the New Teams account picker cache, and resets OneDrive work/school sync connections.

You may need to sign back in and relink OneDrive after reboot.

## Before you run a script

1. Save your work.
2. Close any Teams calls or Outlook compose windows.
3. Run the command that matches your issue.
4. If using the reboot script, the computer will reboot automatically.
5. After cleanup, sign back in with your normal work email address if prompted.

For the reboot script, also open **Company Portal** after reboot, select the device, and choose **Sync** or **Check status**.

## What each script changes

### `Clear-TeamsCache.ps1`

By default, this script:

- Stops Teams processes.
- Clears New Teams cache:
  - `%LocalAppData%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams`
  - `%LocalAppData%\Packages\MSTeams_8wekyb3d8bbwe\TempState`
- Clears Classic Teams cache:
  - `%AppData%\Microsoft\Teams\Cache`
  - `%AppData%\Microsoft\Teams\Code Cache`
  - `%AppData%\Microsoft\Teams\GPUCache`
  - `%AppData%\Microsoft\Teams\IndexedDB`
  - `%AppData%\Microsoft\Teams\Local Storage`
  - `%AppData%\Microsoft\Teams\tmp`
- Relaunches Teams unless `-NoLaunch` is used.

With `-IncludeIdentityCache`, it also clears:

- `%LocalAppData%\Microsoft\OneAuth`
- `%LocalAppData%\Microsoft\TokenBroker`
- `%LocalAppData%\Microsoft\IdentityCache`

### `Clear-NewOutlookAccounts.ps1`

By default, this script:

- Stops New Outlook processes.
- Clears New Outlook for Windows app data:
  - `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\LocalCache`
  - `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\LocalState`
  - `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\RoamingState`
  - `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\Settings`
  - `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\TempState`
  - `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\AC`
- Uses `Reset-AppxPackage` for `Microsoft.OutlookForWindows` when available.
- Leaves New Outlook closed so users can open classic Outlook instead.
- Clears Microsoft identity cache folders:
  - `%LocalAppData%\Microsoft\OneAuth`
  - `%LocalAppData%\Microsoft\TokenBroker`
  - `%LocalAppData%\Microsoft\IdentityCache`
  - `%LocalAppData%\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker`

### `Clear-ClassicOutlookProfiles.ps1`

By default, this script:

- Stops classic Outlook processes.
- Creates a dated backup folder under `%LocalAppData%\Microsoft\Outlook\Backups`.
- Exports profile/settings registry keys for Office 16.0 and 15.0.
- Moves `*.ost`, `*.nst`, and `RoamCache` from `%LocalAppData%\Microsoft\Outlook` into the backup folder.
- Removes classic Outlook profile registry keys for Office 16.0 and 15.0.
- Removes classic Outlook `DefaultProfile` values for Office 16.0 and 15.0.
- Leaves PST files in place.
- Leaves Outlook closed.

### `Clear-WorkAccountsAndReboot.ps1`

All modes:

- Stops Teams, OneDrive, Outlook, Word, Excel, PowerPoint, OneNote, and related Office apps.
- Clears Teams desktop cache.
- Removes Windows Credential Manager entries that match the selected tenant.
- Installs Microsoft Company Portal with `winget install --id 9WZDNCRFJ3PZ --source msstore -e` when `winget` is available.
- Reboots the computer.

Tenant matching uses these known IDs/domains:

- ETG: `80240792-cbae-4f23-942c-b82db959df1b`, `eagletg.com`, `eagletg.net`, `eagletgus.onmicrosoft.com`, `aquilarey.com`
- RCTG: `befedfad-14ec-423b-8dc8-3289d325c95b`, `redcedartg.com`, `redcedartgus.onmicrosoft.com`, `modocfsg.com`, `tumbijv.com`

`-Tenant ALL` also:

- Removes broader Microsoft 365 credentials for Office, Teams, OneDrive, OneAuth, Outlook, AAD, MSOID, and ADAL.
- Resets Office identity, licensing, activation, roaming identity, web service, services manager, and registration state for Office 15.0/16.0 in the current Windows profile.
- Clears Office license cache folders.
- Removes cached Office Click-to-Run user/tenant values when the script has permission.
- Signs out Office WAM accounts for the current Windows profile.
- Resets OneDrive and removes work/school OneDrive account state.
- Clears Microsoft identity/account-picker caches.

## What these scripts do not change

They do not delete or modify:

- Windows local accounts
- Active Directory domain accounts
- Windows user profiles
- Local documents or desktop files
- Domain join or Entra join
- Microsoft 365 tenant configuration
- Teams chat history stored in Microsoft 365
- Outlook mailbox data stored in Microsoft 365
- PST archive files
- Classic Outlook mail profiles, unless a script explicitly says it handles classic Outlook
- Entra users or guest accounts

The reboot script prints `dsregcmd /status` tenant and join state before cleanup.
If `TenantId`, `AzureAdPrtAuthority`, or `WorkplaceJoined` still points to the old tenant after `-Tenant ALL` and reboot, the stale GUID is coming from Windows Access work/school or Entra device registration rather than only app caches.

The scripts do not automatically remove **Settings > Accounts > Access work or school** entries, run `dsregcmd /leave`, or unjoin/rejoin the device. Those steps can disconnect or unmanage a device, so handle them manually or through IT device management if the old tenant remains.

## More details

- [Cache and sign-in locations explained](docs/cache-and-sign-in-locations.md)

## Review a script before running

To view a script instead of running it:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-TeamsCache.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-NewOutlookAccounts.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-ClassicOutlookProfiles.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```
