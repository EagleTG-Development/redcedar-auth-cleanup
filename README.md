# RedCedar/EagleTG stale Microsoft 365 auth cleanup

Temporary break/fix script for Windows users whose Teams, OneDrive, or Office apps are stuck on stale RedCedar/Eagle cross-tenant sign-in state.

## Run RCTG cleanup

Open PowerShell and run:

```powershell
irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

This default mode is equivalent to `-Tenant RCTG` and removes only RedCedarTG-scoped Credential Manager entries it can identify by tenant GUID, tenant name, or domain hints.

## Run ETG cleanup

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ETG
```

## Run both tenant-scoped cleanups

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant Both
```

## Clear all Microsoft 365 logins for this Windows profile

Use this only when tenant-scoped cleanup is not enough:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ALL
```

`-Tenant ALL` removes ETG/RCTG-scoped credentials, removes broad Office, Teams, OneDrive, AAD, MSOID, and ADAL Credential Manager targets, and clears the current-user AAD Broker token cache. `-ClearAllLogins` can also be used with `-Tenant ETG`, `-Tenant RCTG`, or `-Tenant Both`.

## What it changes

All modes:

- Stops Teams, OneDrive, and Office apps.
- Clears Teams desktop cache folders.
- Removes tenant-scoped Windows Credential Manager entries matching the selected tenant hints.
- Forces a reboot.

Tenant hints include:

- EagleTG: `80240792-cbae-4f23-942c-b82db959df1b`, `eagletg.com`, `eagletg.net`, `eagletgus.onmicrosoft.com`, `aquilarey.com`
- RedCedarTG: `befedfad-14ec-423b-8dc8-3289d325c95b`, `redcedartg.com`, `redcedartgus.onmicrosoft.com`, `modocfsg.com`, `tumbijv.com`

With `-Tenant ALL` or `-ClearAllLogins`, it also:

- Removes broad Microsoft 365 Credential Manager entries, including Office, Teams, OneDrive, AAD, MSOID, and ADAL targets.
- Clears current-user AAD Broker token cache folders.

## Effect on other Microsoft 365 tenants

Tenant-scoped mode is intended to avoid clearing unrelated tenants, but Credential Manager target names are not always tenant-specific. Teams cache cleanup is app-wide.

`-Tenant ALL` or `-ClearAllLogins` may sign the current Windows user out of other Microsoft 365 tenants, including Source-Tenant sessions, because it removes broad Microsoft 365 credentials and clears AAD Broker token cache. It does not delete those cloud accounts; users may need to sign back into those apps after reboot.

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
