# RedCedar stale Microsoft 365 auth cleanup

Temporary break/fix script for Windows users whose Teams, OneDrive, or Office apps are stuck on stale RedCedar/Eagle cross-tenant sign-in state.

## Run

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1 | iex
```

The script gives a short cancellation window, closes Microsoft 365 apps, clears RedCedar-related local auth state, and reboots the computer.

## What it changes

- Stops Teams, OneDrive, and Office apps.
- Clears Teams desktop cache folders.
- Removes Windows Credential Manager entries containing RedCedar tenant/domain hints:
  - `redcedartg.com`
  - `redcedartgus.onmicrosoft.com`
  - `modocfsg.com`
  - `tumbijv.com`
- Clears current-user AAD Broker token cache folders.
- Forces a reboot.

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
irm https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1
```
