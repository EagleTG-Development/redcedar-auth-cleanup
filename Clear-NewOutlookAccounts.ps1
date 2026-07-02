<#
.SYNOPSIS
Clears local New Outlook for Windows account and app state for the current Windows user.

.DESCRIPTION
Stops New Outlook processes and removes local app data folders for the New Outlook
for Windows package. This is intended for cases where New Outlook keeps showing
stale accounts, tenant choices, mailbox selections, or sign-in state after the
Microsoft 365 account or tenant has been corrected.

New Outlook does not use classic Outlook MAPI mail profiles. This script only
changes local New Outlook app data for the current Windows profile. It does not
delete mail from Microsoft 365, remove Entra users, change tenant configuration,
clear classic Outlook profiles, remove work/school accounts, reboot Windows, or
reset OneDrive/Office licensing state. It does not relaunch New Outlook after cleanup because users should return to classic Outlook.

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
    }

    function Write-Step {
        param([Parameter(Mandatory)][string]$Message)
        Write-Host "==> $Message" -ForegroundColor Cyan
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
            'OutlookForWindows'
        )

        Write-Step 'Stopping New Outlook processes'

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

    Assert-SupportedEnvironment
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
    )

    foreach ($identityPath in $identityCachePaths) {
        Remove-PathTree -Path $identityPath.Path -Description $identityPath.Description
    }

    Write-Host ''
    if ($cleanupState.RemovalWarnings -gt 0) {
        $message = "New Outlook cleanup finished with $($cleanupState.RemovalWarnings) removal warning(s). " +
            'Close New Outlook and rerun if stale account data remains.'
        Write-Warning $message
    } else {
        Write-Host 'New Outlook account cleanup complete.' -ForegroundColor Green
    }

    Write-Host 'Open classic Outlook instead of New Outlook.' -ForegroundColor Green
}

Invoke-NewOutlookAccountCleanup @PSBoundParameters
