<#
.SYNOPSIS
Clears local Outlook account/profile state for the current Windows user.

.DESCRIPTION
Stops classic Outlook and New Outlook, backs up Outlook profile registry keys,
moves local OST/NST cache files and RoamCache into a dated backup folder, removes
classic Outlook mail profile registry keys, and clears New Outlook app/account
state for the current Windows profile.

Backups are written under:
%LocalAppData%\Microsoft\Outlook\Backups\yyyyMMdd-HHmmss

This script clears both classic Outlook MAPI profiles and New Outlook for Windows
app state. It does not delete mailbox data from Microsoft 365, remove Entra users,
change tenant configuration, remove work/school accounts, reboot Windows, or reset
OneDrive/Office licensing state.

The script does not move PST files. PST files may contain local-only archive data
and should be handled manually.

.EXAMPLE
.\Clear-ClassicOutlookProfiles.ps1

.EXAMPLE
.\Clear-ClassicOutlookProfiles.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

function Invoke-ClassicOutlookProfileCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $cleanupState = @{
        BackupPath = $null
        RegistryBackupFailures = 0
        TranscriptPath = $null
        Warnings = 0
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
        $path = Join-Path $env:TEMP "Clear-ClassicOutlookProfiles-$timestamp.log"

        try {
            Start-Transcript -Path $path -Force | Out-Null
            Write-Host "Transcript log: $path" -ForegroundColor Cyan
            $cleanupState.TranscriptPath = $path
        } catch {
            $cleanupState.Warnings++
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

    function Stop-OutlookProcess {
        Write-Step 'Stopping Outlook processes'

        $processes = @(Get-Process -Name 'OUTLOOK', 'olk', 'OutlookForWindows' -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            $target = "$($process.ProcessName) pid $($process.Id)"
            if ($PSCmdlet.ShouldProcess($target, 'Stop process')) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }

    function New-OutlookBackupFolder {
        $backupRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook\Backups'
        Assert-SafeOutlookPath -Path $backupRoot

        $backupPath = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
        Assert-SafeOutlookPath -Path $backupPath

        if ($PSCmdlet.ShouldProcess($backupPath, 'Create Outlook backup folder')) {
            New-Item -Path $backupPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $cleanupState.BackupPath = $backupPath
        return $backupPath
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
                $cleanupState.RegistryBackupFailures++
                $cleanupState.Warnings++
                Write-Warning "Could not export ${Description}: reg.exe exit code $($process.ExitCode)"
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
                $cleanupState.Warnings++
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
                $cleanupState.Warnings++
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
                $cleanupState.Warnings++
                Write-Warning "Could not move ${Path}: $($_.Exception.Message)"
            }
        }
    }

    function Move-OutlookCacheFiles {
        param([Parameter(Mandatory)][string]$BackupPath)

        $outlookDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
        Assert-SafeOutlookPath -Path $outlookDataPath

        if (-not (Test-Path -LiteralPath $outlookDataPath)) {
            Write-Host "Skip missing: Outlook local data folder ($outlookDataPath)" -ForegroundColor DarkGray
            return
        }

        $cacheFiles = @(
            Get-ChildItem -LiteralPath $outlookDataPath -Filter '*.ost' -File -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $outlookDataPath -Filter '*.nst' -File -Force -ErrorAction SilentlyContinue
        )

        foreach ($cacheFile in $cacheFiles) {
            Move-OutlookItemToBackup `
                -Path $cacheFile.FullName `
                -BackupPath $BackupPath `
                -Description 'classic Outlook cache file'
        }

        $roamCachePath = Join-Path $outlookDataPath 'RoamCache'
        Move-OutlookItemToBackup -Path $roamCachePath -BackupPath $BackupPath -Description 'classic Outlook RoamCache'

        $pstFiles = @(Get-ChildItem -LiteralPath $outlookDataPath -Filter '*.pst' -File -Force -ErrorAction SilentlyContinue)
        foreach ($pstFile in $pstFiles) {
            Write-Warning "Leaving PST file in place: $($pstFile.FullName)"
        }
    }

    function Assert-SafeLocalAppDataPath {
        param([Parameter(Mandatory)][string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Refusing to clean an empty path.'
        }

        if (Test-PathWithinRoot -Path $Path -Root $env:LOCALAPPDATA) {
            return
        }

        throw "Refusing to clean path outside the current user's local app data folder: $Path"
    }

    function Remove-PathContents {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Description
        )

        Assert-SafeLocalAppDataPath -Path $Path

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, "Clear $Description")) {
            try {
                $children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
            } catch {
                $cleanupState.Warnings++
                Write-Warning "Could not list ${Path}: $($_.Exception.Message)"
                return
            }

            foreach ($child in $children) {
                try {
                    Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
                } catch {
                    $cleanupState.Warnings++
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

        Assert-SafeLocalAppDataPath -Path $Path

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, "Remove $Description")) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            } catch {
                $cleanupState.Warnings++
                Write-Warning "Could not remove ${Path}: $($_.Exception.Message)"
            }
        }
    }

    function Clear-NewOutlookAccountState {
        Write-Step 'Resetting New Outlook app package'
        $resetCommand = Get-Command -Name Reset-AppxPackage -ErrorAction SilentlyContinue
        if ($resetCommand) {
            $packages = @(Get-AppxPackage -Name 'Microsoft.OutlookForWindows' -ErrorAction SilentlyContinue)
            foreach ($package in $packages) {
                if ($PSCmdlet.ShouldProcess($package.PackageFullName, 'Reset New Outlook app package')) {
                    try {
                        Reset-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                    } catch {
                        $cleanupState.Warnings++
                        Write-Warning "Could not reset $($package.PackageFullName): $($_.Exception.Message)"
                    }
                }
            }
        } else {
            Write-Warning 'Reset-AppxPackage is not available on this Windows build. Continuing with folder cleanup.'
        }

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
    }

    Assert-SupportedEnvironment
    Start-CleanupTranscript
    try {
    Stop-OutlookProcess
    Start-Sleep -Seconds 2

    Write-Step 'Creating classic Outlook backup folder'
    $backupPath = New-OutlookBackupFolder

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

    if ($cleanupState.RegistryBackupFailures -gt 0) {
        throw 'One or more Outlook registry backups failed. Refusing to remove profiles or move cache files.'
    }

    Write-Step 'Moving classic Outlook OST/NST cache files to backup'
    Move-OutlookCacheFiles -BackupPath $backupPath

    Clear-NewOutlookAccountState

    Write-Step 'Removing classic Outlook mail profiles'
    foreach ($officeVersion in $officeVersions) {
        $profilesPath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook\Profiles"
        $outlookPath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook"

        Remove-RegistryTree -Path $profilesPath -Description "Outlook profiles $officeVersion"
        Remove-RegistryValue -Path $outlookPath -Name 'DefaultProfile' -Description "default profile $officeVersion"
    }

    Write-Host ''
    if ($cleanupState.Warnings -gt 0) {
        $message = "Outlook cleanup finished with $($cleanupState.Warnings) warning(s). " +
            'Review the messages above before opening Outlook.'
        Write-Warning $message
    } else {
        Write-Host 'Outlook cleanup complete.' -ForegroundColor Green
    }

    Write-Host "Backup folder: $($cleanupState.BackupPath)" -ForegroundColor Green
    Write-Host 'Open Outlook and create/sign into a fresh profile if prompted.' -ForegroundColor Green
    } finally {
        Stop-CleanupTranscript
    }
}

Invoke-ClassicOutlookProfileCleanup @PSBoundParameters
