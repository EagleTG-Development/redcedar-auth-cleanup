<#
.SYNOPSIS
Clears selected Microsoft 365 sign-in state and reboots Windows.

.DESCRIPTION
Stops Teams, OneDrive, and Office apps, removes tenant-scoped Windows Credential
Manager entries for EagleTG, RedCedarTG, or both, clears common Teams caches,
ensures Microsoft Company Portal is installed when winget is available, and
forces a reboot.

Use -ClearAllLogins to also remove broad Office, Teams, OneDrive, AAD, MSOID, and
ADAL credentials; clear Microsoft identity caches such as AAD Broker, OneAuth,
TokenBroker, and IdentityCache; reset Office identity/licensing state; sign out
Office WAM accounts; and remove OneDrive work/school account state. That broader
mode may sign the current Windows user out of other Microsoft 365 tenants,
including Source-Tenant sessions.

This script is intended for temporary break/fix use when Teams, OneDrive, or
Office are stuck on stale RedCedar/Eagle cross-tenant sign-in state.

It does not delete Windows local accounts, Active Directory domain accounts,
Windows user profiles, local files, domain join, Entra join, or Microsoft 365
tenant configuration.

This script prints dsregcmd tenant/join state as a read-only diagnostic. It does
not run dsregcmd /leave or remove Settings > Accounts > Access work or school
accounts because doing so can disconnect or unmanage the device. If stale
work/school accounts remain after reboot, remove them manually from Settings or
have IT rejoin/repair the device.

.PARAMETER Tenant
Tenant credential scope to clear. Valid values: RCTG, ETG, Both, ALL. Defaults to RCTG. ALL also enables broad Microsoft 365 login cleanup.

.PARAMETER ClearAllLogins
Also clears broad Microsoft 365 credentials, Office identity/licensing state,
WAM Office accounts, OneDrive work/school account state, and Microsoft identity
caches for the current Windows user. This can sign the user out of other tenants.

.EXAMPLE
irm https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1 | iex

.EXAMPLE
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ETG

.EXAMPLE
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-RedCedarStaleAuthAndReboot.ps1?$(Get-Date -Format yyyyMMddHHmmss)"))) -Tenant ALL
#>

param(
    [ValidateSet('RCTG', 'ETG', 'Both', 'ALL')]
    [string]$Tenant = 'RCTG',

    [switch]$ClearAllLogins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tenantHintMap = @{
    ETG = @(
        '80240792-cbae-4f23-942c-b82db959df1b',
        'EagleTG GCC',
        'eagletg.com',
        'eagletg.net',
        'eagletgus.onmicrosoft.com',
        'aquilarey.com'
    )
    RCTG = @(
        'befedfad-14ec-423b-8dc8-3289d325c95b',
        'Red Cedar TG-MTE LLC',
        'redcedartg.com',
        'redcedartgus.onmicrosoft.com',
        'modocfsg.com',
        'tumbijv.com'
    )
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-ExistingPath {
    param([Parameter(Mandatory)][string[]]$Path)

    return @($Path | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
}

function Get-SelectedTenantHint {
    switch ($Tenant) {
        'ETG' { return @($tenantHintMap.ETG) }
        'RCTG' { return @($tenantHintMap.RCTG) }
        'Both' { return @($tenantHintMap.ETG + $tenantHintMap.RCTG) }
        'ALL' { return @($tenantHintMap.ETG + $tenantHintMap.RCTG) }
    }
}

function Stop-M365App {
    $processNames = @(
        'Teams',
        'ms-teams',
        'msteams',
        'OneDrive',
        'OUTLOOK',
        'olk',
        'WINWORD',
        'EXCEL',
        'POWERPNT',
        'ONENOTE',
        'MSACCESS',
        'MSPUB',
        'VISIO',
        'WINPROJ'
    )

    $oneDrivePaths = Get-ExistingPath -Path @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    )

    foreach ($oneDrivePath in $oneDrivePaths) {
        try {
            Start-Process -FilePath $oneDrivePath -ArgumentList '/shutdown' -Wait -ErrorAction Stop
            Write-Host "Requested OneDrive shutdown: $oneDrivePath"
        }
        catch {
            Write-Warning "Could not request OneDrive shutdown from $oneDrivePath`: $($_.Exception.Message)"
        }
    }

    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $processNames -contains $_.ProcessName } |
        Sort-Object ProcessName, Id

    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Write-Host "Stopped process $($process.ProcessName) [$($process.Id)]"
        }
        catch {
            Write-Warning "Could not stop process $($process.ProcessName) [$($process.Id)]: $($_.Exception.Message)"
        }
    }
}

function Remove-PathIfPresent {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Host "Removed $Path"
    }
    catch {
        Write-Warning "Could not remove $Path`: $($_.Exception.Message)"
    }
}

function Remove-PathByPatternIfPresent {
    param([Parameter(Mandatory)][string]$PathPattern)

    $items = Get-ChildItem -Path $PathPattern -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        Remove-PathIfPresent -Path $item.FullName
    }
}

function Remove-RegistryPathIfPresent {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Host "Removed registry path: $Path"
    }
    catch {
        Write-Warning "Could not remove registry path $Path`: $($_.Exception.Message)"
    }
}

function Get-CurrentUserSid {
    try {
        return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
    catch {
        Write-Warning "Could not determine current user SID: $($_.Exception.Message)"
        return $null
    }
}

function Get-CurrentUserOfficeRegistryRoot {
    $roots = @('HKCU:\Software\Microsoft\Office')
    $currentUserSid = Get-CurrentUserSid
    if ($currentUserSid) {
        $roots += "Registry::HKEY_USERS\$currentUserSid\Software\Microsoft\Office"
    }

    return @($roots | Sort-Object -Unique)
}

function Clear-TeamsCache {
    $paths = @(
        Join-Path $env:APPDATA 'Microsoft\Teams\application cache\cache'
        Join-Path $env:APPDATA 'Microsoft\Teams\blob_storage'
        Join-Path $env:APPDATA 'Microsoft\Teams\Cache'
        Join-Path $env:APPDATA 'Microsoft\Teams\databases'
        Join-Path $env:APPDATA 'Microsoft\Teams\GPUCache'
        Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB'
        Join-Path $env:APPDATA 'Microsoft\Teams\Local Storage'
        Join-Path $env:APPDATA 'Microsoft\Teams\tmp'
        Join-Path $env:APPDATA 'Microsoft\Teams\Cookies'
        Join-Path $env:APPDATA 'Microsoft\Teams\Cookies-journal'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Cache'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\GPUCache'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\IndexedDB'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Local Storage'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Session Storage'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\tmp'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Cookies'
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Cookies-journal'
        Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin\Cache'
        Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin\GPUCache'
    )

    $paths | Sort-Object -Unique | ForEach-Object { Remove-PathIfPresent -Path $_ }
}

function Get-CredentialManagerTarget {
    $cmdkeyOutput = & cmdkey.exe /list 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $cmdkeyOutput) {
        return @()
    }

    $targets = foreach ($line in $cmdkeyOutput) {
        if ($line -match '^\s*Target:\s*(.+?)\s*$') {
            $Matches[1]
        }
    }

    return @($targets | Sort-Object -Unique)
}

function Remove-CredentialTargetByPattern {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$Pattern
    )

    $targets = Get-CredentialManagerTarget | Where-Object {
        $target = $_
        $Pattern | Where-Object { $target -like $_ }
    }

    if (@($targets).Count -eq 0) {
        Write-Host "No $Label Credential Manager targets found."
        return
    }

    foreach ($target in $targets) {
        & cmdkey.exe "/delete:$target" | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removed credential target: $target"
        }
        else {
            Write-Warning "Could not remove credential target: $target"
        }
    }
}

function Remove-TenantCredential {
    $patterns = @(Get-SelectedTenantHint | ForEach-Object { "*$_*" })
    Remove-CredentialTargetByPattern -Label "$Tenant tenant-scoped" -Pattern $patterns
}

function Remove-Microsoft365Credential {
    Remove-CredentialTargetByPattern -Label 'Microsoft 365/Office/Teams/OneDrive' -Pattern @(
        '*MicrosoftOffice*',
        '*MicrosoftOffice*_Data:*',
        '*MicrosoftOffice*_ADAL*',
        '*Microsoft_OC*',
        '*OneDrive*',
        '*OneDrive Cached Credential*',
        '*OneAuth*',
        '*SSO_POP_Device*',
        '*ADAL*',
        '*MSOID*',
        '*AAD*',
        '*Outlook*',
        '*Teams*',
        '*MSTeams*',
        '*msteams*',
        '*MicrosoftTeams*',
        '*SkypeSpaces*'
    )
}

function Clear-MicrosoftIdentityCache {
    $paths = @(
        Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
        Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
        Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth'
        Join-Path $env:LOCALAPPDATA 'Microsoft\TokenBroker'
        Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache'
        Join-Path $env:LOCALAPPDATA 'Microsoft\Olk'
    )

    $paths | ForEach-Object { Remove-PathIfPresent -Path $_ }
}

function Clear-ProtectedStorageSystemValue {
    $paths = @('HKCU:\Software\Microsoft\Protected Storage System')
    $currentUserSid = Get-CurrentUserSid
    if ($currentUserSid) {
        $paths += "Registry::HKEY_USERS\$currentUserSid\Software\Microsoft\Protected Storage System"
    }

    foreach ($path in ($paths | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        try {
            $key = Get-Item -LiteralPath $path -ErrorAction Stop
            foreach ($valueName in $key.GetValueNames()) {
                Remove-ItemProperty -LiteralPath $path -Name $valueName -Force -ErrorAction Stop
                Write-Host "Removed registry value: $path\$valueName"
            }
        }
        catch {
            Write-Warning "Could not clear registry values under $path`: $($_.Exception.Message)"
        }
    }
}

function Clear-OfficeClickToRunConfiguration {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        try {
            $key = Get-Item -LiteralPath $path -ErrorAction Stop
            foreach ($valueName in $key.GetValueNames()) {
                $isCachedUserValue =
                    $valueName -like '*.EmailAddress' -or
                    $valueName -like '*.TenantId' -or
                    $valueName.Equals('ProductKeys', [StringComparison]::OrdinalIgnoreCase)

                if ($isCachedUserValue) {
                    Remove-ItemProperty -LiteralPath $path -Name $valueName -Force -ErrorAction Stop
                    Write-Host "Removed Office ClickToRun registry value: $path\$valueName"
                }
            }
        }
        catch {
            Write-Warning "Could not clear Office ClickToRun values under $path`: $($_.Exception.Message)"
        }
    }
}

function Clear-OfficeRegistryState {
    $officeVersions = @('15.0', '16.0')
    $relativeKeys = @(
        'Common\Identity',
        'Common\Roaming\Identities',
        'Common\Internet\WebServiceCache',
        'Common\ServicesManagerCache',
        'Common\Licensing',
        'Registration'
    )

    foreach ($root in Get-CurrentUserOfficeRegistryRoot) {
        foreach ($officeVersion in $officeVersions) {
            foreach ($relativeKey in $relativeKeys) {
                Remove-RegistryPathIfPresent -Path "$root\$officeVersion\$relativeKey"
            }
        }
    }

    Clear-ProtectedStorageSystemValue
    Clear-OfficeClickToRunConfiguration
}

function Clear-OfficeLicenseCache {
    $paths = @(
        Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses'
        Join-Path $env:LOCALAPPDATA 'Microsoft\Office\15.0\Licensing'
        Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Licensing'
        Join-Path $env:LOCALAPPDATA 'Microsoft\Licenses'
    )

    $paths | ForEach-Object { Remove-PathIfPresent -Path $_ }
}

function Wait-WinRtAction {
    param([Parameter(Mandatory)]$WinRtAction)

    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.GetParameters().Count -eq 1 -and
            -not $_.IsGenericMethod
        } |
        Select-Object -First 1

    $task = $asTask.Invoke($null, @($WinRtAction))
    $task.Wait(-1) | Out-Null
}

function Wait-WinRtOperation {
    param(
        [Parameter(Mandatory)]$WinRtOperation,
        [Parameter(Mandatory)][Type]$ResultType
    )

    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } |
        Select-Object -First 1

    $genericTask = $asTask.MakeGenericMethod($ResultType)
    $task = $genericTask.Invoke($null, @($WinRtOperation))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

function Invoke-OfficeWamSignOut {
    $officeClientId = 'd3590ed6-52b3-4102-aeff-aad2292ab01c'

    try {
        $apiInformation = [Windows.Foundation.Metadata.ApiInformation,Windows,ContentType=WindowsRuntime]
        $webAccountManager = [Windows.Security.Authentication.Web.Core.WebAuthenticationCoreManager,Windows,ContentType=WindowsRuntime]
        $webAccountProviderType = [Windows.Security.Credentials.WebAccountProvider,Windows,ContentType=WindowsRuntime]
        $findAccountsResultType = [Windows.Security.Authentication.Web.Core.FindAllAccountsResult,Windows,ContentType=WindowsRuntime]

        if (-not $apiInformation::IsMethodPresent(
            'Windows.Security.Authentication.Web.Core.WebAuthenticationCoreManager',
            'FindAllAccountsAsync'
        )) {
            Write-Warning 'Office WAM sign-out is not supported on this Windows version.'
            return
        }

        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop

        $providerOperation = $webAccountManager::FindAccountProviderAsync(
            'https://login.microsoft.com',
            'organizations'
        )
        $provider = Wait-WinRtOperation `
            -WinRtOperation $providerOperation `
            -ResultType $webAccountProviderType

        if (-not $provider) {
            Write-Host 'No organizational WAM account provider found.'
            return
        }

        $accountsOperation = $webAccountManager::FindAllAccountsAsync(
            $provider,
            $officeClientId
        )
        $accountsResult = Wait-WinRtOperation `
            -WinRtOperation $accountsOperation `
            -ResultType $findAccountsResultType

        $accounts = @($accountsResult.Accounts)
        if ($accounts.Count -eq 0) {
            Write-Host 'No Office WAM accounts found.'
            return
        }

        foreach ($account in $accounts) {
            Wait-WinRtAction -WinRtAction ($account.SignOutAsync($officeClientId))
            Write-Host 'Signed out one Office WAM account.'
        }
    }
    catch {
        Write-Warning "Could not sign out Office WAM accounts: $($_.Exception.Message)"
    }
}

function Invoke-OneDriveReset {
    $oneDrivePaths = Get-ExistingPath -Path @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    )

    $oneDrivePath = $oneDrivePaths | Select-Object -First 1
    if (-not $oneDrivePath) {
        Write-Host 'No OneDrive executable found to reset.'
        return
    }

    try {
        Start-Process -FilePath $oneDrivePath -ArgumentList '/reset' -Wait -ErrorAction Stop
        Write-Host "Requested OneDrive reset: $oneDrivePath"
    }
    catch {
        Write-Warning "Could not request OneDrive reset from $oneDrivePath`: $($_.Exception.Message)"
    }
}

function Clear-OneDriveAccountState {
    Invoke-OneDriveReset
    Start-Sleep -Seconds 2
    Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $accountRoot = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path -LiteralPath $accountRoot) {
        $businessAccounts = Get-ChildItem -LiteralPath $accountRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -like 'Business*' }

        foreach ($businessAccount in $businessAccounts) {
            Remove-RegistryPathIfPresent -Path $businessAccount.PSPath
        }
    }

    Remove-PathIfPresent -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\cache')
    $businessSettingsPattern = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\settings\Business*'
    $preSignInSettingsPath = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\settings\PreSignInSettingsConfig.json'

    Remove-PathByPatternIfPresent -PathPattern $businessSettingsPattern
    Remove-PathIfPresent -Path $preSignInSettingsPath
}

function Get-DsRegStatusValue {
    param(
        [Parameter(Mandatory)][string[]]$Status,
        [Parameter(Mandatory)][string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    foreach ($line in $Status) {
        if ($line -match "^\s*$escapedName\s*:\s*(.*?)\s*$") {
            return $Matches[1]
        }
    }

    return $null
}

function Install-CompanyPortal {
    $winget = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warning 'winget.exe was not found. Install Microsoft Company Portal from Microsoft Store after reboot.'
        return
    }

    $arguments = @(
        'install',
        '--id', '9WZDNCRFJ3PZ',
        '--source', 'msstore',
        '-e',
        '--accept-source-agreements',
        '--accept-package-agreements'
    )

    try {
        $process = Start-Process `
            -FilePath $winget.Source `
            -ArgumentList $arguments `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-Host 'Microsoft Company Portal is installed or already available.'
            return
        }

        Write-Warning "winget could not install Microsoft Company Portal. Exit code: $($process.ExitCode)"
        Write-Warning 'Install Microsoft Company Portal from Microsoft Store after reboot if it is missing.'
    }
    catch {
        Write-Warning "Could not run winget to install Microsoft Company Portal: $($_.Exception.Message)"
        Write-Warning 'Install Microsoft Company Portal from Microsoft Store after reboot if it is missing.'
    }
}

function Show-DsRegStatusSummary {
    try {
        $status = & dsregcmd.exe /status 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $status) {
            Write-Host 'Could not read dsregcmd status.'
            return
        }

        $fields = [ordered]@{
            AzureAdJoined       = Get-DsRegStatusValue -Status $status -Name 'AzureAdJoined'
            DomainJoined        = Get-DsRegStatusValue -Status $status -Name 'DomainJoined'
            TenantId            = Get-DsRegStatusValue -Status $status -Name 'TenantId'
            TenantName          = Get-DsRegStatusValue -Status $status -Name 'TenantName'
            WorkplaceJoined     = Get-DsRegStatusValue -Status $status -Name 'WorkplaceJoined'
            WamDefaultSet       = Get-DsRegStatusValue -Status $status -Name 'WamDefaultSet'
            AzureAdPrt          = Get-DsRegStatusValue -Status $status -Name 'AzureAdPrt'
            AzureAdPrtAuthority = Get-DsRegStatusValue -Status $status -Name 'AzureAdPrtAuthority'
        }

        Write-Host 'Windows account/device join state from dsregcmd /status:'
        foreach ($field in $fields.GetEnumerator()) {
            if ($field.Value) {
                Write-Host "  $($field.Key): $($field.Value)"
            }
        }

        $statusText = $status -join "`n"
        $matchedTenantHints = @(Get-SelectedTenantHint | Where-Object {
            $statusText -match [regex]::Escape($_)
        })

        if ($matchedTenantHints.Count -gt 0) {
            Write-Warning 'dsregcmd still reports one of the selected tenant IDs/domains.'
            Write-Warning (
                'If that remains after reboot, the stale GUID is in Windows ' +
                'Access work/school or Entra registration.'
            )
        }

        if ($fields.WorkplaceJoined -eq 'YES') {
            Write-Warning (
                'WorkplaceJoined is YES. If sign-in still goes to the old tenant, ' +
                'remove the stale work/school account.'
            )
        }
    }
    catch {
        Write-Warning "Could not read dsregcmd status: $($_.Exception.Message)"
    }
}

Write-Warning 'This will close Teams, OneDrive, and Office apps.'
Write-Warning "It will clear $Tenant tenant-scoped Microsoft 365 sign-in hints and reboot this computer."
if ($Tenant -eq 'ALL') {
    $ClearAllLogins = $true
}

if ($ClearAllLogins) {
    Write-Warning 'Broad login cleanup is enabled. This may sign the user out of other Microsoft 365 tenants.'
    Write-Warning 'It will also reset OneDrive work/school sync connections for this Windows profile.'
}

Show-DsRegStatusSummary

Write-Warning 'Save your work now. Press Ctrl+C within 20 seconds to cancel.'
Start-Sleep -Seconds 20

Write-Step 'Stopping Teams, OneDrive, and Office apps'
Stop-M365App

Write-Step 'Clearing Teams caches'
Clear-TeamsCache

Write-Step "Removing $Tenant tenant-scoped Windows Credential Manager entries"
Remove-TenantCredential

if ($ClearAllLogins) {
    Write-Step 'Removing broad Office, Teams, OneDrive, and Microsoft 365 credentials'
    Remove-Microsoft365Credential

    Write-Step 'Resetting Office identity, licensing, and activation state'
    Clear-OfficeRegistryState
    Clear-OfficeLicenseCache

    Write-Step 'Signing out Office WAM accounts'
    Invoke-OfficeWamSignOut

    Write-Step 'Resetting OneDrive work/school account state'
    Clear-OneDriveAccountState

    Write-Step 'Clearing Microsoft identity and account picker caches'
    Clear-MicrosoftIdentityCache
}

Write-Step 'Ensuring Microsoft Company Portal is installed'
Install-CompanyPortal

Write-Host 'Cleanup complete. Rebooting in 30 seconds.' -ForegroundColor Yellow
Write-Host 'After reboot, sign in with your normal work email address.' -ForegroundColor Yellow
Write-Host 'Open Company Portal, select the device, and sync or check status.' -ForegroundColor Yellow
Start-Sleep -Seconds 30

Restart-Computer -Force
