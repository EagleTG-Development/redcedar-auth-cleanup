<#
.SYNOPSIS
Clears selected Microsoft 365 sign-in state and reboots Windows.

.DESCRIPTION
Stops Teams, OneDrive, and Office apps, removes tenant-scoped Windows Credential
Manager entries for EagleTG, RedCedarTG, or both, clears common Teams caches, and
forces a reboot.

Use -ClearAllLogins to also remove broad Office, Teams, OneDrive, AAD, MSOID, and
ADAL credentials and clear Microsoft identity caches such as AAD Broker, OneAuth,
TokenBroker, and IdentityCache. That broader mode may sign the current Windows
user out of other Microsoft 365 tenants, including Source-Tenant sessions.

This script is intended for temporary break/fix use when Teams, OneDrive, or
Office are stuck on stale RedCedar/Eagle cross-tenant sign-in state.

It does not delete Windows local accounts, Active Directory domain accounts,
Windows user profiles, local files, domain join, Entra join, or Microsoft 365
tenant configuration.

PowerShell does not provide a safe supported way to remove only one specific
Settings > Accounts > Access work or school account by tenant/domain. If stale
work/school accounts remain after reboot, remove them manually from Settings.

.PARAMETER Tenant
Tenant credential scope to clear. Valid values: RCTG, ETG, Both, ALL. Defaults to RCTG. ALL also enables broad Microsoft 365 login cleanup.

.PARAMETER ClearAllLogins
Also clears broad Microsoft 365 Credential Manager targets and AAD Broker token
cache for the current Windows user. This can sign the user out of other tenants.

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
        '*MicrosoftOffice*_Data:*',
        '*MicrosoftOffice*_ADAL*',
        '*OneDrive Cached Credential*',
        '*SSO_POP_Device*',
        '*ADAL*',
        '*MSOID*',
        '*AAD*',
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
    )

    $paths | ForEach-Object { Remove-PathIfPresent -Path $_ }
}

Write-Warning 'This will close Teams, OneDrive, and Office apps.'
Write-Warning "It will clear $Tenant tenant-scoped Microsoft 365 sign-in hints and reboot this computer."
if ($Tenant -eq 'ALL') {
    $ClearAllLogins = $true
}

if ($ClearAllLogins) {
    Write-Warning 'Broad login cleanup is enabled. This may sign the user out of other Microsoft 365 tenants.'
}
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

    Write-Step 'Clearing Microsoft identity and account picker caches'
    Clear-MicrosoftIdentityCache
}

Write-Host 'Cleanup complete. Rebooting in 30 seconds.' -ForegroundColor Yellow
Write-Host 'After reboot, sign in with your normal work email address.' -ForegroundColor Yellow
Start-Sleep -Seconds 30

Restart-Computer -Force
