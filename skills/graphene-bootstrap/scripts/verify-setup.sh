#!/usr/bin/env bash
# verify-setup.sh — Verify GrapheneOS phone setup is complete
#
# Checks that all expected apps are installed, sing-box and Orbot are
# running, VPN is active, battery optimization is whitelisted, and
# the sing-box config is present on the device.
#
# Requirements:
#   - adb connected to device
#
# Usage:
#   bash verify-setup.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; ((PASS++)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; ((WARN++)); }
section() { echo -e "\n${CYAN}=== $* ===${NC}"; }

# --- All expected packages ---

EXPECTED_APPS=(
    "org.fdroid.fdroid|F-Droid"
    "org.mozilla.firefox|Firefox"
    "eu.siacs.conversations|Conversations"
    "io.element.android.x|Element X"
    "chat.fluffy.fluffychat|FluffyChat"
    "org.atalk.android|aTalk"
    "chat.simplex.app|SimpleX Chat"
    "de.tutao.tutanota|Tuta Mail"
    "io.nekohasekai.sfa|sing-box SFA"
    "app.attestation.auditor|Auditor"
    "com.aurora.store|Aurora Store"
    "pw.faraday.faraday|Faraday"
    "com.zoffcc.applications.trifa|TRIfA"
    "com.brave.browser|Brave Browser"
    "ch.threema.app.libre|Threema Libre"
    "network.loki.messenger|Session"
    "org.torproject.android|Orbot"
    "chat.schildi.android|SchildiChat Next"
    "org.maintainteam.hypatia|Hypatia"
    "org.torproject.torbrowser|Tor Browser"
    "com.m2049r.xmrwallet|Monerujo"
    "com.cakewallet.cake_wallet|Cake Wallet"
    "com.monero.app|Monero.com"
    "com.cypherstack.stackwallet|Stack Wallet"
)

# Aurora Store apps (installed separately)
AURORA_APPS=(
    "org.telegram.messenger|Telegram"
    "ch.protonmail.android|Proton Mail"
)

# System/preinstalled (just check, don't fail)
SYSTEM_APPS=(
    "app.vanadium.browser|Vanadium"
    "app.grapheneos.update.client|GrapheneOS Updater"
)

# Services that should be running
EXPECTED_RUNNING=(
    "org.torproject.android|Orbot"
    "io.nekohasekai.sfa|sing-box SFA"
)

# Battery optimization whitelist
BATTERY_WHITELIST=(
    "org.torproject.android|Orbot"
    "io.nekohasekai.sfa|sing-box SFA"
)

# --- Connectivity check ---

echo -e "${CYAN}=== GrapheneOS Setup Verification ===${NC}"
echo "Timestamp: $(date -Iseconds)"

if ! command -v adb &>/dev/null; then
    echo -e "${RED}adb not found${NC}"
    exit 1
fi

adb_count=$(adb devices 2>/dev/null | grep -cE '\tdevice$') || true
if [[ "$adb_count" -eq 0 ]]; then
    echo -e "${RED}No ADB device connected.${NC}"
    exit 1
fi

model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
android=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
graphene=$(adb shell getprop ro.grapheneos.version 2>/dev/null | tr -d '\r')
echo "Device: $model (Android $android, GrapheneOS $graphene)"

# Cache installed packages
mapfile -t INSTALLED_PKGS < <(adb shell pm list packages 2>/dev/null | sed 's/package://' | tr -d '\r')

is_installed() {
    local pkg="$1"
    for p in "${INSTALLED_PKGS[@]}"; do
        [[ "$p" == "$pkg" ]] && return 0
    done
    return 1
}

# --- 1. App installation ---

section "1. F-Droid & Main Apps"
for entry in "${EXPECTED_APPS[@]}"; do
    IFS='|' read -r pkg name <<< "$entry"
    if is_installed "$pkg"; then
        pass "$name ($pkg)"
    else
        fail "$name ($pkg) — not installed"
    fi
done

section "2. Aurora Store Apps"
for entry in "${AURORA_APPS[@]}"; do
    IFS='|' read -r pkg name <<< "$entry"
    if is_installed "$pkg"; then
        pass "$name ($pkg)"
    else
        warn "$name ($pkg) — not installed (install from Aurora Store)"
    fi
done

section "3. System Apps"
for entry in "${SYSTEM_APPS[@]}"; do
    IFS='|' read -r pkg name <<< "$entry"
    if is_installed "$pkg"; then
        pass "$name ($pkg)"
    else
        warn "$name ($pkg) — not found (expected on GrapheneOS)"
    fi
done

# --- 2. Services running ---

section "4. Running Services"
for entry in "${EXPECTED_RUNNING[@]}"; do
    IFS='|' read -r pkg name <<< "$entry"
    if adb shell "ps -A -o NAME" 2>/dev/null | grep -q "$pkg"; then
        pass "$name is running"
    else
        fail "$name is NOT running"
    fi
done

# --- 3. VPN status ---

section "5. VPN Status"
vpn_pkg=$(adb shell settings get secure always_on_vpn_app 2>/dev/null | tr -d '\r') || true
if [[ "$vpn_pkg" == "io.nekohasekai.sfa" ]]; then
    pass "Always-on VPN: sing-box SFA"
elif [[ -n "$vpn_pkg" && "$vpn_pkg" != "null" ]]; then
    warn "Always-on VPN set to: $vpn_pkg (expected io.nekohasekai.sfa)"
else
    fail "No always-on VPN configured"
fi

vpn_lockdown=$(adb shell settings get secure always_on_vpn_lockdown 2>/dev/null | tr -d '\r') || true
if [[ "$vpn_lockdown" == "1" ]]; then
    pass "VPN lockdown (block without VPN) enabled"
else
    warn "VPN lockdown not enabled — traffic may leak if VPN disconnects"
fi

# --- 4. Battery optimization ---

section "6. Battery Optimization Whitelist"
whitelist_output=$(adb shell dumpsys deviceidle whitelist 2>/dev/null) || true
for entry in "${BATTERY_WHITELIST[@]}"; do
    IFS='|' read -r pkg name <<< "$entry"
    if echo "$whitelist_output" | grep -q "$pkg"; then
        pass "$name whitelisted"
    else
        fail "$name NOT whitelisted — may be killed in background"
    fi
done

# --- 5. sing-box config ---

section "7. sing-box Config"
if adb shell "test -f /sdcard/Download/singbox-config.json" 2>/dev/null; then
    pass "singbox-config.json present in /sdcard/Download/"
else
    warn "singbox-config.json not found in /sdcard/Download/ (may already be imported)"
fi

# Check if sing-box has an active profile by looking at its data
sfa_config_count=$(adb shell "ls /data/data/io.nekohasekai.sfa/files/ 2>/dev/null | wc -l" 2>/dev/null | tr -d '\r') || sfa_config_count="0"
if [[ "$sfa_config_count" -gt 0 ]]; then
    pass "sing-box SFA has data files (profile likely imported)"
else
    warn "sing-box SFA data directory empty or inaccessible"
fi

# --- 6. Orbot config ---

section "8. Orbot Configuration"
# Check if Orbot is listening on expected SOCKS ports
ORBOT_UID=$(adb shell "ps -A -o UID,NAME" 2>/dev/null \
    | grep 'org.torproject.android' | awk '{print $1}' | head -1) || true

if [[ -n "$ORBOT_UID" ]]; then
    port_count=$(adb shell "cat /proc/net/tcp" 2>/dev/null \
        | awk -v uid="$ORBOT_UID" '
            $4 == "0A" && $8 == uid {
                split($2, a, ":")
                port = strtonum("0x" a[2])
                if (port >= 9050 && port <= 9999) count++
            }
            END { print count+0 }
        ') || port_count="0"

    if [[ "$port_count" -ge 16 ]]; then
        pass "Orbot has $port_count SOCKS ports listening (expected 16+)"
    elif [[ "$port_count" -gt 0 ]]; then
        warn "Orbot has $port_count SOCKS ports (expected 16+ for per-app isolation)"
    else
        fail "Orbot has no SOCKS ports listening"
    fi

    # Check DNS port
    dns_listening=$(adb shell "cat /proc/net/tcp" 2>/dev/null \
        | awk -v uid="$ORBOT_UID" '
            $4 == "0A" && $8 == uid {
                split($2, a, ":")
                port = strtonum("0x" a[2])
                if (port == 5400) found=1
            }
            END { print found+0 }
        ') || dns_listening="0"

    if [[ "$dns_listening" == "1" ]]; then
        pass "Orbot DNSPort 5400 listening"
    else
        fail "Orbot DNSPort 5400 NOT listening"
    fi
else
    fail "Orbot not running — cannot check ports"
fi

# --- 7. OEM unlock disabled ---

section "9. Security"
oem_unlock=$(adb shell settings get global oem_unlock_allowed 2>/dev/null | tr -d '\r') || true
if [[ "$oem_unlock" == "0" ]]; then
    pass "OEM unlocking disabled"
elif [[ "$oem_unlock" == "1" ]]; then
    warn "OEM unlocking still enabled — disable in Developer options"
else
    warn "Could not check OEM unlock status"
fi

# Check USB debugging reminder
usb_debug=$(adb shell settings get global adb_enabled 2>/dev/null | tr -d '\r') || true
if [[ "$usb_debug" == "1" ]]; then
    warn "USB debugging is ON — disable after setup for security"
fi

# --- Summary ---

section "Summary"

echo ""
echo "Passed:   $PASS"
echo "Failed:   $FAIL"
echo "Warnings: $WARN"
echo ""

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo -e "${GREEN}ALL CHECKS PASSED. Setup is complete.${NC}"
elif [[ $FAIL -eq 0 ]]; then
    echo -e "${YELLOW}All critical checks passed. Review warnings above.${NC}"
else
    echo -e "${RED}$FAIL check(s) failed. Review and fix the issues above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "  Missing apps    → re-run: bash setup-android-apps.sh"
    echo "  Service not running → start Orbot/sing-box manually on the device"
    echo "  No VPN          → Settings > Network > VPN > set sing-box as always-on"
    echo "  Battery whitelist → adb shell dumpsys deviceidle whitelist +<package>"
    echo "  Tor isolation   → bash verify-tor-isolation.sh"
fi
