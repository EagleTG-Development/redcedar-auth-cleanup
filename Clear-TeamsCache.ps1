<#
.SYNOPSIS
Clears local Microsoft Teams desktop cache for the current Windows user.

.DESCRIPTION
Stops Microsoft Teams processes and removes common New Teams and Classic Teams
cache folders for the current Windows profile. This is intended for cases where
Teams keeps resolving stale people, chats, or tenant identities after the tenant
object has been corrected.

This script only changes local Teams cache files. It does not delete Teams chat
history from Microsoft 365, remove Entra users, change tenant configuration,
clear Office/OneDrive sign-in state, reboot Windows, or remove work/school
accounts. By default, it relaunches Teams after cleanup.

.PARAMETER IncludeIdentityCache
Also clears Teams-adjacent local account picker/token cache folders that can keep
stale Microsoft identity selections. This may sign Teams or other Microsoft apps
out for the current Windows profile.

.PARAMETER NoLaunch
Do not relaunch Teams after clearing cache folders.

.EXAMPLE
.\Clear-TeamsCache.ps1

.EXAMPLE
.\Clear-TeamsCache.ps1 -IncludeIdentityCache

.EXAMPLE
.\Clear-TeamsCache.ps1 -NoLaunch

.EXAMPLE
.\Clear-TeamsCache.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeIdentityCache,

    [switch]$NoLaunch
)

function Invoke-TeamsCacheCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$IncludeIdentityCache,

        [switch]$NoLaunch
    )

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
        Assert-WindowsProfilePath -Name 'APPDATA' -Path $env:APPDATA
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
            $env:LOCALAPPDATA,
            $env:APPDATA
        )

        foreach ($root in $allowedRoots) {
            if (Test-PathWithinRoot -Path $normalizedPath -Root $root) {
                return
            }
        }

        throw "Refusing to clean path outside the current user's app data folders: $Path"
    }

    function Stop-TeamsProcess {
        $processNames = @(
            'Teams',
            'ms-teams',
            'msteams'
        )

        Write-Step 'Stopping Teams processes'

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

    function Start-TeamsApp {
        Write-Step 'Launching Teams'

        $launchTargets = @(
            @{
                Kind = 'Uri'
                Value = 'shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams'
                Description = 'New Teams app package'
            }
            @{
                Kind = 'File'
                Value = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\ms-teams.exe'
                Description = 'New Teams WindowsApps executable'
            }
            @{
                Kind = 'File'
                Value = Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe'
                Description = 'Classic Teams executable'
            }
            @{
                Kind = 'Uri'
                Value = 'msteams:'
                Description = 'Teams protocol handler'
            }
        )

        foreach ($launchTarget in $launchTargets) {
            if ($launchTarget.Kind -eq 'File' -and -not (Test-Path -LiteralPath $launchTarget.Value)) {
                continue
            }

            try {
                if ($PSCmdlet.ShouldProcess($launchTarget.Description, 'Start Teams')) {
                    Start-Process -FilePath $launchTarget.Value -ErrorAction Stop
                }
                return
            } catch {
                $message = "Launch failed for $($launchTarget.Description): $($_.Exception.Message)"
                Write-Host $message -ForegroundColor DarkGray
            }
        }

        Write-Warning 'Teams cache was cleared, but Teams could not be relaunched automatically. Start Teams manually.'
    }

    Assert-SupportedEnvironment
    Stop-TeamsProcess
    Start-Sleep -Seconds 2

    Write-Step 'Clearing Teams cache folders'

    $newTeamsCachePaths = @(
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
            Description = 'New Teams MSTeams cache'
        }
        @{
            Path = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\TempState'
            Description = 'New Teams temp state'
        }
    )

    $classicTeamsCachePaths = @(
        @{
            Path = Join-Path $env:APPDATA 'Microsoft\Teams\Cache'
            Description = 'Classic Teams cache'
        }
        @{
            Path = Join-Path $env:APPDATA 'Microsoft\Teams\Code Cache'
            Description = 'Classic Teams code cache'
        }
        @{
            Path = Join-Path $env:APPDATA 'Microsoft\Teams\GPUCache'
            Description = 'Classic Teams GPU cache'
        }
        @{
            Path = Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB'
            Description = 'Classic Teams IndexedDB'
        }
        @{
            Path = Join-Path $env:APPDATA 'Microsoft\Teams\Local Storage'
            Description = 'Classic Teams local storage'
        }
        @{
            Path = Join-Path $env:APPDATA 'Microsoft\Teams\tmp'
            Description = 'Classic Teams temp cache'
        }
    )

    foreach ($cachePath in @($newTeamsCachePaths + $classicTeamsCachePaths)) {
        Remove-PathContents -Path $cachePath.Path -Description $cachePath.Description
    }

    if ($IncludeIdentityCache) {
        Write-Warning 'This also clears Microsoft identity caches and may sign out Teams or other Microsoft apps.'
        Write-Step 'Clearing Teams-adjacent identity cache folders'

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
        )

        foreach ($identityPath in $identityCachePaths) {
            Remove-PathTree -Path $identityPath.Path -Description $identityPath.Description
        }
    }

    if (-not $NoLaunch) {
        Start-TeamsApp
    }

    Write-Host ''
    if ($cleanupState.RemovalWarnings -gt 0) {
        $message = "Teams cache cleanup finished with $($cleanupState.RemovalWarnings) removal warning(s). " +
            'Close Teams and rerun if stale data remains.'
        Write-Warning $message
    } else {
        Write-Host 'Teams cache cleanup complete.' -ForegroundColor Green
    }

    if ($NoLaunch) {
        Write-Host 'Reopen Teams and start a new chat by typing the full email address.' -ForegroundColor Green
    } else {
        Write-Host 'Start a new chat by typing the full email address.' -ForegroundColor Green
    }
}

Invoke-TeamsCacheCleanup @PSBoundParameters
