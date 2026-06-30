# Microsoft 365 sign-in cleanup for RedCedar / EagleTG

Use this when Teams, OneDrive, or Office keeps trying to sign in to the wrong RedCedar/EagleTG tenant or shows stale sign-in errors.

The script closes Microsoft 365 apps, clears local sign-in cache, installs Microsoft Company Portal when `winget` is available, and reboots the computer.

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

`-Tenant ALL` may sign you out of other Microsoft 365 tenants or organizations on this Windows profile.
It also resets Office sign-in/licensing state, signs out Office WAM accounts,
clears the New Teams account picker cache, and resets OneDrive work/school sync connections.

You may need to sign back in and relink OneDrive after reboot.

## Before you run it

1. Save your work.
2. Close any Teams calls or meetings.
3. Run the right command above in PowerShell.
4. The script gives you a short chance to cancel.
5. The computer will reboot automatically.
6. After reboot, sign in with your normal work email address.
7. Open **Company Portal**, select the device, and choose **Sync** or **Check status**.

## What this script changes

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
- Resets Office identity, licensing, activation, roaming identity, web service,
  services manager, and registration state for Office 15.0/16.0 in the current Windows profile.
- Clears Office license cache folders:
  - `%LocalAppData%\Microsoft\Office\Licenses`
  - `%LocalAppData%\Microsoft\Office\15.0\Licensing`
  - `%LocalAppData%\Microsoft\Office\16.0\Licensing`
  - `%LocalAppData%\Microsoft\Licenses`
- Removes cached Office Click-to-Run user/tenant values when the script has permission.
- Signs out Office WAM accounts for the current Windows profile.
- Resets OneDrive and removes work/school OneDrive account state:
  - `HKCU\Software\Microsoft\OneDrive\Accounts\Business*`
  - `%LocalAppData%\Microsoft\OneDrive\cache`
  - `%LocalAppData%\Microsoft\OneDrive\settings\Business*`
  - `%LocalAppData%\Microsoft\OneDrive\settings\PreSignInSettingsConfig.json`
- Clears Microsoft identity/account-picker caches:
  - `%LocalAppData%\Packages\MSTeams_8wekyb3d8bbwe`
  - `%LocalAppData%\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy`
  - `%LocalAppData%\Microsoft\OneAuth`
  - `%LocalAppData%\Microsoft\TokenBroker`
  - `%LocalAppData%\Microsoft\IdentityCache`
  - `%LocalAppData%\Microsoft\Olk`

## What this script does not change

It does not delete or modify:

- Windows local accounts
- Active Directory domain accounts
- Windows user profiles
- local files
- domain join or Entra join
- Microsoft 365 tenant configuration

The script prints `dsregcmd /status` tenant and join state before cleanup.
If `TenantId`, `AzureAdPrtAuthority`, or `WorkplaceJoined` still points to the old tenant
after `-Tenant ALL` and reboot, the stale GUID is coming from Windows Access work/school
or Entra device registration rather than only app caches.

It does not automatically remove **Settings > Accounts > Access work or school** entries,
run `dsregcmd /leave`, or unjoin/rejoin the device.
Those steps can disconnect or unmanage a device, so handle them manually or through IT device management
if the old tenant remains.

## Review the script before running

To view the script instead of running it:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```
