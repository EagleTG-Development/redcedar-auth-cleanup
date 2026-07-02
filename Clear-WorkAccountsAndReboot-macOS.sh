#!/bin/bash
#
# Clear-WorkAccountsAndReboot-macOS.sh
#
# macOS equivalent of Clear-WorkAccountsAndReboot.ps1
# Stops Microsoft 365 apps, clears tenant-scoped Keychain entries,
# removes Teams/OneDrive/Office caches, and reboots.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot-macOS.sh | bash
#   curl -sL https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot-macOS.sh | bash -s -- --tenant ETG
#   curl -sL https://raw.githubusercontent.com/EagleTG-Development/redcedar-auth-cleanup/main/Clear-WorkAccountsAndReboot-macOS.sh | bash -s -- --tenant ALL
#
# Parameters:
#   --tenant RCTG|ETG|Both|ALL  (default: RCTG)
#   --clear-all                 Also clears broad M365 login state (equivalent to -ClearAllLogins)
#   --no-reboot                 Skip the reboot (cleanup only)
#

set -euo pipefail

TENANT="RCTG"
CLEAR_ALL=false
NO_REBOOT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant) TENANT="${2:-RCTG}"; shift 2 ;;
        --clear-all) CLEAR_ALL=true; shift ;;
        --no-reboot) NO_REBOOT=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

TENANT=$(echo "$TENANT" | tr '[:lower:]' '[:upper:]')
if [[ ! "$TENANT" =~ ^(RCTG|ETG|BOTH|ALL)$ ]]; then
    echo "Invalid tenant: $TENANT. Use RCTG, ETG, Both, or ALL."
    exit 1
fi

if [[ "$TENANT" == "ALL" ]]; then
    CLEAR_ALL=true
fi

# Tenant hints for Keychain search
ETG_HINTS=(
    "80240792-cbae-4f23-942c-b82db959df1b"
    "eagletg.com"
    "eagletg.net"
    "eagletgus.onmicrosoft.com"
    "aquilarey.com"
)

RCTG_HINTS=(
    "befedfad-14ec-423b-8dc8-3289d325c95b"
    "redcedartg.com"
    "redcedartgus.onmicrosoft.com"
    "modocfsg.com"
    "tumbijv.com"
)

get_tenant_hints() {
    case "$TENANT" in
        ETG) printf '%s\n' "${ETG_HINTS[@]}" ;;
        RCTG) printf '%s\n' "${RCTG_HINTS[@]}" ;;
        BOTH|ALL) printf '%s\n' "${ETG_HINTS[@]}" "${RCTG_HINTS[@]}" ;;
    esac
}

log_step() {
    echo ""
    echo "==> $1"
}

log_ok() {
    echo "    $1"
}

log_warn() {
    echo "    [WARN] $1"
}

# --- Transcript ---
LOGFILE="$HOME/Desktop/Clear-WorkAccounts-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Transcript: $LOGFILE"
echo "Tenant scope: $TENANT"
echo "Clear all logins: $CLEAR_ALL"
echo "User: $(whoami)"
echo "Date: $(date)"
echo ""

# --- Warning ---
echo "WARNING: This will close Teams, OneDrive, Outlook, and Office apps."
echo "WARNING: It will clear $TENANT tenant-scoped Microsoft 365 sign-in state and reboot."
if $CLEAR_ALL; then
    echo "WARNING: Broad login cleanup enabled. This may sign you out of other Microsoft 365 tenants."
fi
echo ""
echo "Save your work now. Press Ctrl+C within 10 seconds to cancel."
sleep 10

# --- Stop Microsoft 365 apps ---
log_step "Stopping Microsoft 365 apps"

APPS_TO_KILL=(
    "Microsoft Teams"
    "Microsoft Teams (work or school)"
    "Microsoft Teams classic"
    "OneDrive"
    "Microsoft Outlook"
    "Microsoft Word"
    "Microsoft Excel"
    "Microsoft PowerPoint"
    "Microsoft OneNote"
    "Company Portal"
)

for app in "${APPS_TO_KILL[@]}"; do
    if pgrep -xq "$app" 2>/dev/null || pgrep -f "$app" >/dev/null 2>&1; then
        osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
        sleep 1
        pkill -f "$app" 2>/dev/null || true
        log_ok "Stopped: $app"
    fi
done

pkill -f "com.microsoft.teams" 2>/dev/null || true
pkill -f "MSTeams" 2>/dev/null || true

# Kill SSO-related daemons
pkill -9 AppSSOAgent 2>/dev/null || true
pkill -9 swcd 2>/dev/null || true
log_ok "Stopped SSO extension daemons"

# --- Clear Teams caches ---
log_step "Clearing Teams caches"

TEAMS_CACHE_PATHS=(
    "$HOME/Library/Application Support/Microsoft/Teams"
    "$HOME/Library/Caches/com.microsoft.teams"
    "$HOME/Library/Caches/com.microsoft.teams2"
    "$HOME/Library/Group Containers/UBF8T346G9.com.microsoft.teams"
    "$HOME/Library/Containers/com.microsoft.teams2"
    "$HOME/Library/Application Support/com.microsoft.teams2"
)

for path in "${TEAMS_CACHE_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        rm -rf "$path" 2>/dev/null && log_ok "Removed: $path" || log_warn "Could not remove: $path"
    fi
done

# --- Clear OneDrive caches ---
log_step "Clearing OneDrive caches"

ONEDRIVE_CACHE_PATHS=(
    "$HOME/Library/Caches/com.microsoft.OneDrive"
    "$HOME/Library/Caches/com.microsoft.OneDriveStandaloneUpdater"
    "$HOME/Library/Containers/com.microsoft.OneDrive-mac"
    "$HOME/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite"
    "$HOME/Library/Logs/OneDrive"
)

for path in "${ONEDRIVE_CACHE_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        rm -rf "$path" 2>/dev/null && log_ok "Removed: $path" || log_warn "Could not remove: $path"
    fi
done

# --- Remove tenant-scoped Keychain entries ---
log_step "Removing $TENANT tenant-scoped Keychain entries"

while IFS= read -r hint; do
    # Search login keychain for entries matching tenant hints
    entries=$(security find-generic-password -l "$hint" 2>/dev/null | grep "svce" | sed 's/.*="//;s/"//' || true)
    if [[ -n "$entries" ]]; then
        while IFS= read -r entry; do
            security delete-generic-password -s "$entry" 2>/dev/null && log_ok "Removed keychain entry: $entry" || true
        done <<< "$entries"
    fi

    # Also try by account
    security delete-generic-password -a "$hint" 2>/dev/null && log_ok "Removed keychain by account: $hint" || true
    security delete-internet-password -a "$hint" 2>/dev/null && log_ok "Removed internet keychain: $hint" || true
    security delete-generic-password -s "$hint" 2>/dev/null && log_ok "Removed keychain by service: $hint" || true
done < <(get_tenant_hints)

# Remove Microsoft-specific Keychain entries for the tenant
MICROSOFT_KEYCHAIN_SERVICES=(
    "com.microsoft.adalcache"
    "com.microsoft.identity.universalstorage"
    "com.microsoft.identity.broker"
    "com.microsoft.identity.universalauth"
    "com.microsoft.workplacejoin"
    "com.microsoft.OneDrive.authentication"
    "Microsoft Office Identities Cache"
    "Microsoft Office Identities Cache 2"
    "Microsoft Office Identities Settings"
    "Microsoft Office Identities Settings 2"
    "Microsoft Office Ticket Cache"
)

# Remove Primary Refresh Token entries (SSO extension PRT)
PRT_BROKER_ID="primaryrefreshtoken-29d9ed98-a469-4536-ade2-f981bc1d605e"
security delete-generic-password -l "$PRT_BROKER_ID" 2>/dev/null && log_ok "Removed PRT entry" || true

for svc in "${MICROSOFT_KEYCHAIN_SERVICES[@]}"; do
    security delete-generic-password -s "$svc" 2>/dev/null && log_ok "Removed: $svc" || true
done

# --- Broad cleanup (if --clear-all or ALL) ---
if $CLEAR_ALL; then
    log_step "Clearing broad Microsoft 365 identity state"

    # Office identity/license caches
    OFFICE_IDENTITY_PATHS=(
        "$HOME/Library/Group Containers/UBF8T346G9.Office/MicrosoftRegistrationDB.reg"
        "$HOME/Library/Group Containers/UBF8T346G9.Office/DRM"
        "$HOME/Library/Group Containers/UBF8T346G9.Office/Licenses"
        "$HOME/Library/Group Containers/UBF8T346G9.Office/OfficeOsfPluginCache"
        "$HOME/Library/Group Containers/UBF8T346G9.Office/com.microsoft.Office365.plist"
        "$HOME/Library/Group Containers/UBF8T346G9.Office/com.microsoft.e0E2OUQxNULw.plist"
        "$HOME/Library/Containers/com.microsoft.Outlook/Data/Library/Caches"
        "$HOME/Library/Preferences/com.microsoft.office.plist"
    )

    for path in "${OFFICE_IDENTITY_PATHS[@]}"; do
        if [[ -e "$path" ]]; then
            rm -rf "$path" 2>/dev/null && log_ok "Removed: $path" || log_warn "Could not remove: $path"
        fi
    done

    # SSO extension / Enterprise SSO tokens
    log_step "Clearing SSO extension state"
    BROKER_PATHS=(
        "$HOME/Library/Group Containers/UBF8T346G9.com.microsoft.identity"
        "$HOME/Library/Containers/com.microsoft.CompanyPortalMac.ssoextension"
        "$HOME/Library/Application Support/com.microsoft.CompanyPortal"
        "$HOME/Library/Application Support/com.apple.SSOAgent"
        "$HOME/Library/Caches/com.apple.SSOAgent"
    )

    for path in "${BROKER_PATHS[@]}"; do
        if [[ -e "$path" ]]; then
            rm -rf "$path" 2>/dev/null && log_ok "Removed: $path" || log_warn "Could not remove: $path"
        fi
    done

    # Kill SSO/broker processes to release token state
    pkill -f "Microsoft Single Sign On" 2>/dev/null || true
    pkill -f "com.microsoft.CompanyPortalMac" 2>/dev/null || true

    # Reset associated domain validation cache (SSO extension domain trust)
    sudo swcutil reset 2>/dev/null && log_ok "Reset associated domain validation cache" || true

    # Remove all Microsoft Keychain entries (broad)
    log_step "Removing all Microsoft-related Keychain entries"
    security dump-keychain 2>/dev/null | grep 'svce' | sed 's/.*<blob>="//;s/".*//' | grep -i "microsoft\|office\|teams\|onedrive\|outlook\|adal\|msal" | sort -u | while IFS= read -r svc; do
        security delete-generic-password -s "$svc" 2>/dev/null && log_ok "Removed: $svc" || true
    done
fi

# --- Clear preferences (plists survive cache deletion) ---
log_step "Clearing Microsoft 365 preferences (defaults delete)"

PLIST_DOMAINS=(
    "com.microsoft.teams2"
    "com.microsoft.Teams"
    "com.microsoft.OneDrive"
)

if $CLEAR_ALL; then
    PLIST_DOMAINS+=(
        "com.microsoft.Outlook"
        "com.microsoft.Office"
        "com.microsoft.office.licensingV2"
        "com.microsoft.autoupdate2"
    )
fi

for domain in "${PLIST_DOMAINS[@]}"; do
    defaults delete "$domain" 2>/dev/null && log_ok "Cleared plist: $domain" || true
done

# --- Reset OneDrive ---
log_step "Resetting OneDrive"
if [[ -d "/Applications/OneDrive.app" ]]; then
    open /Applications/OneDrive.app --args --reset 2>/dev/null &
    sleep 3
    pkill -f "OneDrive" 2>/dev/null || true
    log_ok "OneDrive reset requested"
else
    log_warn "OneDrive.app not found in /Applications"
fi

# --- Flush DNS (helps with federation endpoint resolution) ---
log_step "Flushing DNS cache"
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true
log_ok "DNS cache flushed"

# --- Summary ---
echo ""
echo "============================================"
echo " Cleanup complete."
echo " Transcript saved: $LOGFILE"
echo "============================================"
echo ""
echo "After reboot:"
echo "  1. Open Microsoft Teams and sign in with your work email"
echo "  2. Open Company Portal and verify device compliance"
echo "  3. Open OneDrive and sign in — libraries will re-sync"
echo ""

if $NO_REBOOT; then
    echo "Reboot skipped (--no-reboot). Restart manually when ready."
    exit 0
fi

echo "Rebooting in 30 seconds. Press Ctrl+C to cancel."
sleep 30

sudo shutdown -r now
