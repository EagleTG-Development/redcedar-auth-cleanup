# Cache and sign-in locations explained

This page explains the main local Windows locations used by the cleanup scripts.
It is for operators who want to understand what each cleanup area is likely to affect.

## Teams cache folders

Teams keeps local app data so it can open quickly and remember recent state.
That cache can include search results, local web/app data, temporary files, and cached contact or chat metadata.

The Teams-only script clears common New Teams and Classic Teams cache folders:

- `%LocalAppData%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams`
- `%LocalAppData%\Packages\MSTeams_8wekyb3d8bbwe\TempState`
- `%AppData%\Microsoft\Teams\Cache`
- `%AppData%\Microsoft\Teams\Code Cache`
- `%AppData%\Microsoft\Teams\GPUCache`
- `%AppData%\Microsoft\Teams\IndexedDB`
- `%AppData%\Microsoft\Teams\Local Storage`
- `%AppData%\Microsoft\Teams\tmp`

Clearing these folders does not delete Teams chat history from Microsoft 365.
It only removes local Teams desktop cache for the current Windows user.

## New Outlook app data folders

New Outlook for Windows stores local account and app state in its Windows app package data, not in classic Outlook MAPI profiles.
The New Outlook cleanup script and `Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` clear these package folders for the current Windows user:

- `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\LocalCache`
- `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\LocalState`
- `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\RoamingState`
- `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\Settings`
- `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\TempState`
- `%LocalAppData%\Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe\AC`

The script also uses `Reset-AppxPackage` for `Microsoft.OutlookForWindows` when that cmdlet is available.

Clearing these folders does not delete mailbox data from Microsoft 365.
It only removes local New Outlook app/account state for the current Windows user.

## Classic Outlook profile and cache locations

Classic Outlook mail profiles are stored in the current user's Office registry keys:

- `HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles`
- `HKCU:\Software\Microsoft\Office\15.0\Outlook\Profiles`

`Clear-ClassicOutlookProfiles.ps1` and `Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` export those keys, plus the matching Outlook settings keys, into a dated backup folder under:

- `%LocalAppData%\Microsoft\Outlook\Backups\yyyyMMdd-HHmmss-fff`

If a registry export fails, the script stops before moving cache files or removing profiles.
It then removes the profile keys and `DefaultProfile` values.
The script also moves these local cache items into the same backup folder:

- `%LocalAppData%\Microsoft\Outlook\*.ost`
- `%LocalAppData%\Microsoft\Outlook\*.nst`
- `%LocalAppData%\Microsoft\Outlook\RoamCache`

PST files are left in place because they may contain local-only archive data.

## Microsoft identity cache folders

The `-IncludeIdentityCache` option in `Clear-TeamsCache.ps1` removes Microsoft identity cache folders.
`Clear-NewOutlookAccounts.ps1` always removes these identity cache folders:

- `%LocalAppData%\Microsoft\OneAuth`
- `%LocalAppData%\Microsoft\TokenBroker`
- `%LocalAppData%\Microsoft\IdentityCache`

`Clear-NewOutlookAccounts.ps1`, `Clear-OneDriveWorkAccount.ps1`, and `Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` also remove:

- `%LocalAppData%\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker`
- `%LocalAppData%\Packages\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\AC\TokenBroker\Accounts`

These locations can contain local Microsoft account picker, token broker, tenant, and sign-in session metadata.
Clearing them can help when Teams or New Outlook still prefers an old account or tenant after the normal app cleanup runs.

Expected impact:

- Teams, Outlook, Office, OneDrive, or other Microsoft apps may ask the user to sign in again.
- Account picker entries may be rebuilt after sign-in.
- Cloud accounts, files, chats, and tenant users are not deleted.

## Windows Credential Manager entries

`Clear-WorkAccountsAndReboot.ps1` can remove Windows Credential Manager entries that match selected RedCedar/EagleTG tenant hints.
Those entries may contain saved app credentials or authentication references for Office, Teams, OneDrive, or related Microsoft sign-in flows.

The script uses tenant IDs, domains, and tenant names to decide which entries match the selected tenant.
`-Tenant ALL` expands the cleanup to broader Microsoft 365 credential patterns.

## Office identity and licensing state

`Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` resets Office identity and licensing state for the current Windows profile.
This is a stronger cleanup path for Office activation or sign-in loops.

Expected impact:

- Office apps may require sign-in after reboot.
- Office licensing may refresh after sign-in.
- Other Microsoft 365 tenants in the same Windows profile may be signed out.

## OneDrive work/school state

`Clear-OneDriveWorkAccount.ps1` and `Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` reset OneDrive and remove work/school OneDrive account state from the current Windows profile.
This can help when OneDrive is stuck on an old tenant or stale account.

`Clear-OneDriveWorkAccount.ps1` and `Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` back up OneDrive registry/settings state under:

- `%LocalAppData%\Microsoft\OneDrive\Backups\yyyyMMdd-HHmmss-fff`

It then removes or clears:

- `HKCU:\Software\Microsoft\OneDrive\Accounts\Business*`
- `%LocalAppData%\Microsoft\OneDrive\cache`
- `%LocalAppData%\Microsoft\OneDrive\settings\Business*`
- `%LocalAppData%\Microsoft\OneDrive\settings\PreSignInSettingsConfig.json`

It also clears Microsoft identity caches and common OneDrive/Microsoft cached Credential Manager entries.

Expected impact:

- OneDrive may need to be set up again after cleanup.
- Teams, Outlook, Office, or other Microsoft apps may ask the user to sign in again.
- Existing cloud files are not deleted.
- Synced OneDrive folders under the user's profile are not deleted or moved.
- Locally synced folders may need to be relinked.

## Device join and Access work or school

The scripts do not remove Windows device registration, Entra join, domain join, or **Settings > Accounts > Access work or school** entries.

That is intentional. Removing those can disconnect a managed device or break compliance enrollment.
If stale tenant IDs remain in `dsregcmd /status` after cache cleanup, handle device registration repair manually or through IT device management.
