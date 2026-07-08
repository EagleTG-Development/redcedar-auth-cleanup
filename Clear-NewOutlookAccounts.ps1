<#
.SYNOPSIS
Clears local Outlook account/app state for the current Windows user.

.DESCRIPTION
Stops New Outlook and classic Outlook processes, removes local New Outlook app
data, and backs up/removes classic Outlook mail profiles. This is intended for
cases where Outlook keeps showing stale accounts, tenant choices, mailbox
selections, or sign-in state after the Microsoft 365 account or tenant has been
corrected.

New Outlook does not use classic Outlook MAPI mail profiles, so this script
clears both New Outlook app/account state and classic Outlook profile state. It
does not delete mail from Microsoft 365, remove Entra users, change tenant
configuration, remove work/school accounts, reboot Windows, or reset
OneDrive/Office licensing state. It does not relaunch Outlook after cleanup.

.EXAMPLE
.\Clear-NewOutlookAccounts.ps1

.EXAMPLE
.\Clear-NewOutlookAccounts.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

function Invoke-NewOutlookAccountCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $cleanupState = @{
        RemovalWarnings = 0
        TranscriptPath = $null
    }

    function Write-Step {
        param([Parameter(Mandatory)][string]$Message)
        Write-Host "==> $Message" -ForegroundColor Cyan
    }

    function Start-CleanupTranscript {
        if ($WhatIfPreference) {
            return
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $path = Join-Path $env:TEMP "Clear-NewOutlookAccounts-$timestamp.log"

        try {
            Start-Transcript -Path $path -Force | Out-Null
            Write-Host "Transcript log: $path" -ForegroundColor Cyan
            $cleanupState.TranscriptPath = $path
        } catch {
            $cleanupState.RemovalWarnings++
            Write-Warning "Could not start transcript logging: $($_.Exception.Message)"
        }
    }

    function Stop-CleanupTranscript {
        if (-not $cleanupState.TranscriptPath) {
            return
        }

        try {
            Stop-Transcript | Out-Null
            Write-Host "Transcript saved: $($cleanupState.TranscriptPath)" -ForegroundColor Cyan
        } catch {
            Write-Warning "Could not stop transcript logging: $($_.Exception.Message)"
        }
    }

    function Assert-WindowsProfilePath {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw "$Name is not set. This script must run in a Windows user profile."
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "$Name does not exist: $Path"
        }
    }

    function Assert-SupportedEnvironment {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            throw 'This script only supports Windows.'
        }

        Assert-WindowsProfilePath -Name 'LOCALAPPDATA' -Path $env:LOCALAPPDATA
    }

    function Get-NormalizedPath {
        param([Parameter(Mandatory)][string]$Path)

        return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    }

    function Test-PathWithinRoot {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Root
        )

        $normalizedPath = Get-NormalizedPath -Path $Path
        $normalizedRoot = Get-NormalizedPath -Path $Root
        $rootPrefix = "$normalizedRoot$([System.IO.Path]::DirectorySeparatorChar)"

        return $normalizedPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    }

    function Assert-SafeCleanupPath {
        param([Parameter(Mandatory)][string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Refusing to clean an empty path.'
        }

        $normalizedPath = Get-NormalizedPath -Path $Path
        $allowedRoots = @(
            $env:LOCALAPPDATA
        )

        foreach ($root in $allowedRoots) {
            if (Test-PathWithinRoot -Path $normalizedPath -Root $root) {
                return
            }
        }

        throw "Refusing to clean path outside the current user's local app data folder: $Path"
    }

    function Stop-NewOutlookProcess {
        $processNames = @(
            'olk',
            'OutlookForWindows',
            'OUTLOOK'
        )

        Write-Step 'Stopping Outlook processes'

        foreach ($processName in $processNames) {
            $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
            foreach ($process in $processes) {
                $target = "$($process.ProcessName) pid $($process.Id)"
                if ($PSCmdlet.ShouldProcess($target, 'Stop process')) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    function Reset-NewOutlookPackage {
        $resetCommand = Get-Command -Name Reset-AppxPackage -ErrorAction SilentlyContinue
        if (-not $resetCommand) {
            Write-Warning 'Reset-AppxPackage is not available on this Windows build. Continuing with folder cleanup.'
            return
        }

        $packages = @(Get-AppxPackage -Name 'Microsoft.OutlookForWindows' -ErrorAction SilentlyContinue)
        if ($packages.Count -eq 0) {
            Write-Host 'Skip missing: Microsoft.OutlookForWindows package' -ForegroundColor DarkGray
            return
        }

        foreach ($package in $packages) {
            if ($PSCmdlet.ShouldProcess($package.PackageFullName, 'Reset New Outlook app package')) {
                try {
                    Reset-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                } catch {
                    $cleanupState.RemovalWarnings++
                    Write-Warning "Could not reset $($package.PackageFullName): $($_.Exception.Message)"
                }
            }
        }
    }

    function Remove-PathContents {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Description
        )

        Assert-SafeCleanupPath -Path $Path

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, "Clear $Description")) {
            try {
                $children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
            } catch {
                $cleanupState.RemovalWarnings++
                Write-Warning "Could not list ${Path}: $($_.Exception.Message)"
                return
            }

            foreach ($child in $children) {
                try {
                    Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
                } catch {
                    $cleanupState.RemovalWarnings++
                    Write-Warning "Could not remove $($child.FullName): $($_.Exception.Message)"
                }
            }
        }
    }

    function Remove-PathTree {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Description
        )

        Assert-SafeCleanupPath -Path $Path

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, "Remove $Description")) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            } catch {
                $cleanupState.RemovalWarnings++
                Write-Warning "Could not remove ${Path}: $($_.Exception.Message)"
            }
        }
    }

    function Assert-SafeOutlookPath {
        param([Parameter(Mandatory)][string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Refusing to use an empty path.'
        }

        $outlookRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
        if (Test-PathWithinRoot -Path $Path -Root $outlookRoot) {
            return
        }

        $normalizedPath = Get-NormalizedPath -Path $Path
        $normalizedRoot = Get-NormalizedPath -Path $outlookRoot
        if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }

        throw "Refusing to use path outside the current user's Outlook local app data folder: $Path"
    }

    function Export-RegistryKey {
        param(
            [Parameter(Mandatory)][string]$RegistryPath,
            [Parameter(Mandatory)][string]$OutputPath,
            [Parameter(Mandatory)][string]$Description
        )

        if (-not (Test-Path -LiteralPath $RegistryPath)) {
            Write-Host "Skip missing: $Description ($RegistryPath)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess($RegistryPath, "Export $Description")) {
            $regExePath = Join-Path $env:SystemRoot 'System32\reg.exe'
            $regPath = $RegistryPath -replace '^HKCU:', 'HKCU'
            $process = Start-Process -FilePath $regExePath `
                -ArgumentList @('export', $regPath, $OutputPath, '/y') `
                -NoNewWindow `
                -PassThru `
                -Wait

            if ($process.ExitCode -ne 0) {
                $cleanupState.RemovalWarnings++
                throw "Could not export ${Description}: reg.exe exit code $($process.ExitCode)"
            }
        }
    }

    function Remove-RegistryTree {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Description
        )

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, "Remove $Description")) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            } catch {
                $cleanupState.RemovalWarnings++
                Write-Warning "Could not remove ${Path}: $($_.Exception.Message)"
            }
        }
    }

    function Remove-RegistryValue {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Description
        )

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if (-not $property) {
            Write-Host "Skip missing: $Description ($Path\$Name)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess("$Path\$Name", "Remove $Description")) {
            try {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
            } catch {
                $cleanupState.RemovalWarnings++
                Write-Warning "Could not remove ${Path}\${Name}: $($_.Exception.Message)"
            }
        }
    }

    function Move-OutlookItemToBackup {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$BackupPath,
            [Parameter(Mandatory)][string]$Description
        )

        Assert-SafeOutlookPath -Path $Path
        Assert-SafeOutlookPath -Path $BackupPath

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        $destination = Join-Path $BackupPath (Split-Path -Path $Path -Leaf)
        if ($PSCmdlet.ShouldProcess($Path, "Move $Description to $destination")) {
            try {
                Move-Item -LiteralPath $Path -Destination $destination -Force -ErrorAction Stop
            } catch {
                $cleanupState.RemovalWarnings++
                Write-Warning "Could not move ${Path}: $($_.Exception.Message)"
            }
        }
    }

    function Clear-ClassicOutlookProfileState {
        Write-Step 'Creating classic Outlook backup folder'
        $backupRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook\Backups'
        Assert-SafeOutlookPath -Path $backupRoot

        $backupPath = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
        Assert-SafeOutlookPath -Path $backupPath

        if ($PSCmdlet.ShouldProcess($backupPath, 'Create Outlook backup folder')) {
            New-Item -Path $backupPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        Write-Step 'Backing up classic Outlook profile registry keys'
        $officeVersions = @('16.0', '15.0')
        foreach ($officeVersion in $officeVersions) {
            $profilesPath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook\Profiles"
            $outlookPath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook"

            Export-RegistryKey `
                -RegistryPath $profilesPath `
                -OutputPath (Join-Path $backupPath "Outlook-Profiles-$officeVersion.reg") `
                -Description "Outlook profiles $officeVersion"

            Export-RegistryKey `
                -RegistryPath $outlookPath `
                -OutputPath (Join-Path $backupPath "Outlook-Settings-$officeVersion.reg") `
                -Description "Outlook settings $officeVersion"
        }

        Write-Step 'Moving classic Outlook OST/NST cache files to backup'
        $outlookDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
        Assert-SafeOutlookPath -Path $outlookDataPath

        if (Test-Path -LiteralPath $outlookDataPath) {
            $cacheFiles = @(
                Get-ChildItem -LiteralPath $outlookDataPath -Filter '*.ost' -File -Force -ErrorAction SilentlyContinue
                Get-ChildItem -LiteralPath $outlookDataPath -Filter '*.nst' -File -Force -ErrorAction SilentlyContinue
            )

            foreach ($cacheFile in $cacheFiles) {
                Move-OutlookItemToBackup `
                    -Path $cacheFile.FullName `
                    -BackupPath $backupPath `
                    -Description 'classic Outlook cache file'
            }

            Move-OutlookItemToBackup `
                -Path (Join-Path $outlookDataPath 'RoamCache') `
                -BackupPath $backupPath `
                -Description 'classic Outlook RoamCache'

            $pstFiles = @(Get-ChildItem -LiteralPath $outlookDataPath -Filter '*.pst' -File -Force -ErrorAction SilentlyContinue)
            foreach ($pstFile in $pstFiles) {
                Write-Warning "Leaving PST file in place: $($pstFile.FullName)"
            }
        }

        Write-Step 'Removing classic Outlook mail profiles'
        foreach ($officeVersion in $officeVersions) {
            $profilesPath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook\Profiles"
            $outlookPath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook"

            Remove-RegistryTree -Path $profilesPath -Description "Outlook profiles $officeVersion"
            Remove-RegistryValue -Path $outlookPath -Name 'DefaultProfile' -Description "default profile $officeVersion"
        }

        Write-Host "Classic Outlook backup folder: $backupPath" -ForegroundColor Green
    }

    Assert-SupportedEnvironment
    Start-CleanupTranscript
    try {
    Stop-NewOutlookProcess
    Start-Sleep -Seconds 2

    Write-Step 'Resetting New Outlook app package'
    Reset-NewOutlookPackage
    Stop-NewOutlookProcess
    Start-Sleep -Seconds 2

    Write-Step 'Clearing New Outlook app data folders'

    $newOutlookPackageRoot = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.OutlookForWindows_8wekyb3d8bbwe'
    $newOutlookDataPaths = @(
        @{
            Path = Join-Path $newOutlookPackageRoot 'LocalCache'
            Description = 'New Outlook local cache'
        }
        @{
            Path = Join-Path $newOutlookPackageRoot 'LocalState'
            Description = 'New Outlook local state'
        }
        @{
            Path = Join-Path $newOutlookPackageRoot 'RoamingState'
            Description = 'New Outlook roaming state'
        }
        @{
            Path = Join-Path $newOutlookPackageRoot 'Settings'
            Description = 'New Outlook settings'
        }
        @{
            Path = Join-Path $newOutlookPackageRoot 'TempState'
            Description = 'New Outlook temp state'
        }
        @{
            Path = Join-Path $newOutlookPackageRoot 'AC'
            Description = 'New Outlook app container cache'
        }
    )

    foreach ($dataPath in $newOutlookDataPaths) {
        Remove-PathContents -Path $dataPath.Path -Description $dataPath.Description
    }

    Remove-PathTree `
        -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\olk') `
        -Description 'New Outlook local profile/cache root'

    Clear-ClassicOutlookProfileState

    $message = 'This also clears Microsoft identity caches and may sign out Outlook, Teams, Office, ' +
        'OneDrive, or other Microsoft apps.'
    Write-Warning $message
    Write-Step 'Clearing Microsoft identity cache folders'

    $identityCachePaths = @(
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth'
            Description = 'OneAuth cache'
        }
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Microsoft\TokenBroker'
            Description = 'TokenBroker cache'
        }
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache'
            Description = 'Microsoft IdentityCache'
        }
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker'
            Description = 'AAD BrokerPlugin TokenBroker cache'
        }
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\AC\TokenBroker\Accounts'
            Description = 'CloudExperienceHost TokenBroker account cache'
        }
    )

    foreach ($identityPath in $identityCachePaths) {
        Remove-PathTree -Path $identityPath.Path -Description $identityPath.Description
    }

    Write-Host ''
    if ($cleanupState.RemovalWarnings -gt 0) {
        $message = "Outlook cleanup finished with $($cleanupState.RemovalWarnings) removal warning(s). " +
            'Close New Outlook and rerun if stale account data remains.'
        Write-Warning $message
    } else {
        Write-Host 'Outlook account cleanup complete.' -ForegroundColor Green
    }

    Write-Host 'Open Outlook and sign into a fresh profile if prompted.' -ForegroundColor Green
    } finally {
        Stop-CleanupTranscript
    }
}

Invoke-NewOutlookAccountCleanup @PSBoundParameters
