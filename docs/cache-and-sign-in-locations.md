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

## Microsoft identity cache folders

The `-IncludeIdentityCache` option in `Clear-TeamsCache.ps1` removes Teams-adjacent Microsoft identity cache folders:

- `%LocalAppData%\Microsoft\OneAuth`
- `%LocalAppData%\Microsoft\TokenBroker`
- `%LocalAppData%\Microsoft\IdentityCache`

These locations can contain local Microsoft account picker, token broker, tenant, and sign-in session metadata.
Clearing them can help when Teams still prefers an old account or tenant after the normal Teams cache is cleared.

Expected impact:

- Teams or other Microsoft apps may ask the user to sign in again.
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

`Clear-WorkAccountsAndReboot.ps1 -Tenant ALL` resets OneDrive and removes work/school OneDrive account state from the current Windows profile.
This can help when OneDrive is stuck on an old tenant or stale account.

Expected impact:

- OneDrive may need to be set up again after reboot.
- Existing cloud files are not deleted.
- Locally synced folders may need to be relinked.

## Device join and Access work or school

The scripts do not remove Windows device registration, Entra join, domain join, or **Settings > Accounts > Access work or school** entries.

That is intentional. Removing those can disconnect a managed device or break compliance enrollment.
If stale tenant IDs remain in `dsregcmd /status` after cache cleanup, handle device registration repair manually or through IT device management.
