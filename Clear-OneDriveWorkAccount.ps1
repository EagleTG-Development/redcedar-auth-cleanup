<#
.SYNOPSIS
Clears OneDrive work/school account and cached sign-in state for the current Windows user.

.DESCRIPTION
Stops OneDrive, requests a OneDrive reset, backs up OneDrive account/settings
state, removes OneDrive work/school account registry keys, clears OneDrive cache
and business settings, clears Microsoft identity caches, and removes common
OneDrive/Microsoft cached Credential Manager entries.

Backups are written under:
%LocalAppData%\Microsoft\OneDrive\Backups\yyyyMMdd-HHmmss-fff

This script does not delete or move synced OneDrive folders under the user's
profile. It only changes OneDrive app/account state and local Microsoft sign-in
caches for the current Windows profile.

.EXAMPLE
.\Clear-OneDriveWorkAccount.ps1

.EXAMPLE
.\Clear-OneDriveWorkAccount.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

function Invoke-OneDriveWorkAccountCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $cleanupState = @{
        BackupPath = $null
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
        $path = Join-Path $env:TEMP "Clear-OneDriveWorkAccount-$timestamp.log"

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

    function Assert-SafeLocalAppDataPath {
        param([Parameter(Mandatory)][string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Refusing to use an empty path.'
        }

        if (Test-PathWithinRoot -Path $Path -Root $env:LOCALAPPDATA) {
            return
        }

        throw "Refusing to use path outside the current user's local app data folder: $Path"
    }

    function Stop-OneDriveProcess {
        Write-Step 'Stopping OneDrive processes'

        $processes = @(Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            $target = "$($process.ProcessName) pid $($process.Id)"
            if ($PSCmdlet.ShouldProcess($target, 'Stop process')) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }

    function Get-OneDriveExecutablePath {
        $candidatePaths = @(
            Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
            Join-Path ${env:ProgramFiles} 'Microsoft OneDrive\OneDrive.exe'
            Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe'
        )

        foreach ($candidatePath in $candidatePaths) {
            if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath)) {
                return $candidatePath
            }
        }

        return $null
    }

    function Invoke-OneDriveReset {
        $oneDrivePath = Get-OneDriveExecutablePath
        if (-not $oneDrivePath) {
            Write-Warning 'OneDrive.exe was not found. Continuing with account and cache cleanup.'
            $cleanupState.Warnings++
            return
        }

        if ($PSCmdlet.ShouldProcess($oneDrivePath, 'Request OneDrive reset')) {
            try {
                $process = Start-Process -FilePath $oneDrivePath `
                    -ArgumentList '/reset' `
                    -NoNewWindow `
                    -PassThru `
                    -Wait

                if ($process.ExitCode -ne 0) {
                    $cleanupState.Warnings++
                    Write-Warning "OneDrive reset exited with code $($process.ExitCode)."
                }
            } catch {
                $cleanupState.Warnings++
                Write-Warning "Could not request OneDrive reset: $($_.Exception.Message)"
            }
        }
    }

    function New-OneDriveBackupFolder {
        $backupRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\Backups'
        Assert-SafeLocalAppDataPath -Path $backupRoot

        $backupPath = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
        Assert-SafeLocalAppDataPath -Path $backupPath

        if ($PSCmdlet.ShouldProcess($backupPath, 'Create OneDrive backup folder')) {
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

    function Copy-ItemToBackup {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$BackupPath,
            [Parameter(Mandatory)][string]$Description
        )

        Assert-SafeLocalAppDataPath -Path $Path
        Assert-SafeLocalAppDataPath -Path $BackupPath

        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Host "Skip missing: $Description ($Path)" -ForegroundColor DarkGray
            return
        }

        $destination = Join-Path $BackupPath (Split-Path -Path $Path -Leaf)
        if ($PSCmdlet.ShouldProcess($Path, "Back up $Description to $destination")) {
            try {
                Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force -ErrorAction Stop
            } catch {
                $cleanupState.Warnings++
                Write-Warning "Could not back up ${Path}: $($_.Exception.Message)"
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

    function Remove-PathByPattern {
        param(
            [Parameter(Mandatory)][string]$PathPattern,
            [Parameter(Mandatory)][string]$Description
        )

        $parentPath = Split-Path -Path $PathPattern -Parent
        Assert-SafeLocalAppDataPath -Path $parentPath

        $items = @(Get-ChildItem -Path $PathPattern -Force -ErrorAction SilentlyContinue)
        if ($items.Count -eq 0) {
            Write-Host "Skip missing: $Description ($PathPattern)" -ForegroundColor DarkGray
            return
        }

        foreach ($item in $items) {
            Remove-PathTree -Path $item.FullName -Description $Description
        }
    }

    function Get-CredentialManagerTarget {
        $cmdkey = Get-Command -Name 'cmdkey.exe' -ErrorAction SilentlyContinue
        if (-not $cmdkey) {
            Write-Warning 'cmdkey.exe was not found. Skipping Credential Manager cleanup.'
            $cleanupState.Warnings++
            return @()
        }

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
            if ($PSCmdlet.ShouldProcess($target, "Remove $Label Credential Manager target")) {
                & cmdkey.exe "/delete:$target" | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Removed credential target: $target"
                } else {
                    $cleanupState.Warnings++
                    Write-Warning "Could not remove credential target: $target"
                }
            }
        }
    }

    Assert-SupportedEnvironment
    Start-CleanupTranscript
    try {
    Stop-OneDriveProcess
    Start-Sleep -Seconds 2

    Write-Step 'Creating OneDrive backup folder'
    $backupPath = New-OneDriveBackupFolder

    Write-Step 'Backing up OneDrive account and settings state'
    Export-RegistryKey `
        -RegistryPath 'HKCU:\Software\Microsoft\OneDrive\Accounts' `
        -OutputPath (Join-Path $backupPath 'OneDrive-Accounts.reg') `
        -Description 'OneDrive account registry state'

    Export-RegistryKey `
        -RegistryPath 'HKCU:\Software\Microsoft\OneDrive' `
        -OutputPath (Join-Path $backupPath 'OneDrive-Settings.reg') `
        -Description 'OneDrive registry settings'

    $oneDriveLocalRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'
    Copy-ItemToBackup `
        -Path (Join-Path $oneDriveLocalRoot 'settings') `
        -BackupPath $backupPath `
        -Description 'OneDrive settings folder'

    Write-Step 'Requesting OneDrive reset'
    Invoke-OneDriveReset
    Start-Sleep -Seconds 2
    Stop-OneDriveProcess

    Write-Step 'Removing OneDrive work/school account registry state'
    $accountRoot = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path -LiteralPath $accountRoot) {
        $businessAccounts = @(Get-ChildItem -LiteralPath $accountRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -like 'Business*' })

        foreach ($businessAccount in $businessAccounts) {
            Remove-RegistryTree -Path $businessAccount.PSPath -Description 'OneDrive work/school account registry key'
        }
    } else {
        Write-Host "Skip missing: OneDrive account registry state ($accountRoot)" -ForegroundColor DarkGray
    }

    Write-Step 'Clearing OneDrive cache and business settings'
    Remove-PathTree -Path (Join-Path $oneDriveLocalRoot 'cache') -Description 'OneDrive cache'
    Remove-PathByPattern `
        -PathPattern (Join-Path $oneDriveLocalRoot 'settings\Business*') `
        -Description 'OneDrive business settings'
    Remove-PathTree `
        -Path (Join-Path $oneDriveLocalRoot 'settings\PreSignInSettingsConfig.json') `
        -Description 'OneDrive pre-sign-in settings'

    Write-Step 'Clearing Microsoft identity caches'
    $identityCachePaths = @(
        Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth'
        Join-Path $env:LOCALAPPDATA 'Microsoft\TokenBroker'
        Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache'
        Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker'
        Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\AC\TokenBroker\Accounts'
    )

    foreach ($identityCachePath in $identityCachePaths) {
        Remove-PathTree -Path $identityCachePath -Description 'Microsoft identity cache'
    }

    Write-Step 'Removing OneDrive and Microsoft cached credentials'
    Remove-CredentialTargetByPattern -Label 'OneDrive/Microsoft cached login' -Pattern @(
        '*OneDrive*',
        '*OneDrive Cached Credential*',
        '*MicrosoftOffice*',
        '*MicrosoftOffice*_Data:*',
        '*MicrosoftOffice*_ADAL*',
        '*OneAuth*',
        '*ADAL*',
        '*MSOID*',
        '*AAD*',
        '*login.microsoftonline.com*',
        '*SSO_POP_Device*'
    )

    Write-Host ''
    if ($cleanupState.Warnings -gt 0) {
        $message = "OneDrive work/school cleanup finished with $($cleanupState.Warnings) warning(s). " +
            'Review the messages above before opening OneDrive.'
        Write-Warning $message
    } else {
        Write-Host 'OneDrive work/school cleanup complete.' -ForegroundColor Green
    }

    Write-Host "Backup folder: $($cleanupState.BackupPath)" -ForegroundColor Green
    Write-Host 'Synced OneDrive folders were not deleted or moved.' -ForegroundColor Green
    Write-Host 'Open OneDrive and sign in with the correct work or school account if needed.' -ForegroundColor Green
    } finally {
        Stop-CleanupTranscript
    }
}

Invoke-OneDriveWorkAccountCleanup @PSBoundParameters
