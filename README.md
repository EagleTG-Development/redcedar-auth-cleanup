# RedCedar stale Microsoft 365 auth cleanup

Temporary break/fix script for Windows users whose Teams, OneDrive, or Office apps are stuck on stale RedCedar/Eagle cross-tenant sign-in state.

## Run

Open PowerShell and run:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

The script gives a short cancellation window, closes Microsoft 365 apps, clears RedCedar-related and broad Microsoft 365 local auth state, and reboots the computer.

## What it changes

- Stops Teams, OneDrive, and Office apps.
- Clears Teams desktop cache folders.
- Removes Windows Credential Manager entries containing RedCedar tenant/domain hints:
  - `redcedartg.com`
  - `redcedartgus.onmicrosoft.com`
  - `modocfsg.com`
  - `tumbijv.com`
- Removes broad Microsoft 365 Credential Manager entries, including Office, Teams, OneDrive, AAD, MSOID, and ADAL targets.
- Clears current-user AAD Broker token cache folders.
- Forces a reboot.

## Effect on other Microsoft 365 tenants

This script may sign the current Windows user out of other Microsoft 365 tenants, including Source-Tenant sessions, because it removes broad Office/Teams/OneDrive/AAD/MSOID/ADAL credentials and clears the current-user AAD Broker token cache. It does not delete those cloud accounts; users may need to sign back into those apps after reboot.

## What it does not change

The script does not delete or modify:

- Windows local accounts
- Active Directory domain accounts
- Windows user profiles
- local files
- domain join or Entra join
- Microsoft 365 tenant configuration

PowerShell does not provide a safe supported way to remove only one specific **Settings > Accounts > Access work or school** account by tenant/domain. If stale work/school accounts remain after reboot, remove them manually from Settings.

## Review before running

Remote execution with `irm ... | iex` should only be used with a trusted URL. To inspect first:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"
```
