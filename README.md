# Microsoft 365 sign-in cleanup for RedCedar / EagleTG

Use this when Teams, OneDrive, or Office keeps trying to sign in to the wrong RedCedar/EagleTG tenant or shows stale sign-in errors.

The script closes Microsoft 365 apps, clears local sign-in cache, and reboots the computer.

## Which command should I use?

### RedCedar / RCTG users

Most RedCedar users should use this:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

### EagleTG / ETG users

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ETG
```

### If you use both RedCedar and EagleTG

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant Both
```

### Last resort: clear all Microsoft 365 logins

Use this only if the commands above do not fix the problem:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ALL
```

`-Tenant ALL` may sign you out of other Microsoft 365 tenants or organizations on this Windows profile. You may need to sign back in after reboot.

## Before you run it

1. Save your work.
2. Close any Teams calls or meetings.
3. Run the right command above in PowerShell.
4. The script gives you a short chance to cancel.
5. The computer will reboot automatically.
6. After reboot, sign in with your normal work email address.

## What this script changes

All modes:

- Stops Teams, OneDrive, Outlook, Word, Excel, PowerPoint, OneNote, and related Office apps.
- Clears Teams desktop cache.
- Removes Windows Credential Manager entries that match the selected tenant.
- Reboots the computer.

Tenant matching uses these known IDs/domains:

- ETG: `80240792-cbae-4f23-942c-b82db959df1b`, `eagletg.com`, `eagletg.net`, `eagletgus.onmicrosoft.com`, `aquilarey.com`
- RCTG: `befedfad-14ec-423b-8dc8-3289d325c95b`, `redcedartg.com`, `redcedartgus.onmicrosoft.com`, `modocfsg.com`, `tumbijv.com`

`-Tenant ALL` also:

- Removes broader Microsoft 365 credentials for Office, Teams, OneDrive, AAD, MSOID, and ADAL.
- Clears the current-user AAD Broker token cache.

## What this script does not change

It does not delete or modify:

- Windows local accounts
- Active Directory domain accounts
- Windows user profiles
- local files
- domain join or Entra join
- Microsoft 365 tenant configuration

It also does not automatically remove **Settings > Accounts > Access work or school** entries. Windows does not provide a safe, tenant-specific PowerShell command for that. If stale work/school accounts remain after reboot, remove them manually from Settings.

## Review the script before running

To view the script instead of running it:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```
