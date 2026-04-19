#!/usr/bin/env bash
# install-aurora-apps.sh — Install Play Store apps via direct APK download
#
# Installs apps not available on F-Droid by downloading official APKs
# and sideloading via ADB. Aurora Store handles future updates.
#
# Currently installs:
#   - Telegram (from telegram.org)
#   - Proton Mail (from GitHub releases)
#
# Requirements:
#   - adb connected to device
#   - curl on this machine
#   - Aurora Store installed (for future updates)
#
# Usage:
#   bash install-aurora-apps.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

INSTALLED=()
FAILED=()

# --- Checks ---

echo -e "${CYAN}=== Install Aurora Store Apps via ADB ===${NC}"

for cmd in adb curl; do
    command -v "$cmd" &>/dev/null || { log_fail "Missing: $cmd"; exit 1; }
done

adb_count=$(adb devices 2>/dev/null | grep -cE '\tdevice$') || true
if [[ "$adb_count" -eq 0 ]]; then
    log_fail "No ADB device connected."
    exit 1
fi

# Cache installed packages
mapfile -t INSTALLED_PKGS < <(adb shell pm list packages 2>/dev/null | sed 's/package://' | tr -d '\r')

is_installed() {
    local pkg="$1"
    for p in "${INSTALLED_PKGS[@]}"; do
        [[ "$p" == "$pkg" ]] && return 0
    done
    return 1
}

# --- Install function ---

install_apk() {
    local pkg="$1"
    local name="$2"
    local url="$3"
    local apk="$TMPDIR/${pkg}.apk"

    printf "  %-20s " "$name"

    if is_installed "$pkg"; then
        echo -e "${YELLOW}already installed${NC}"
        return
    fi

    if ! curl -fSL -o "$apk" "$url" 2>/dev/null; then
        echo -e "${RED}download failed${NC}"
        FAILED+=("$name")
        return
    fi

    if adb install -r "$apk" >/dev/null 2>&1; then
        echo -e "${GREEN}installed${NC}"
        INSTALLED+=("$name")
    else
        echo -e "${RED}adb install failed${NC}"
        FAILED+=("$name")
    fi
}

# --- Telegram ---
# Official APK from telegram.org (includes built-in updater)

log_info "Downloading and installing apps..."
echo ""

install_apk "org.telegram.messenger" "Telegram" \
    "https://telegram.org/dl/android/apk"

# --- Proton Mail ---
# Official APK from GitHub releases (Aurora Store handles updates)

PROTON_APK_URL=$(curl -fsSL "https://api.github.com/repos/ProtonMail/android-mail/releases/latest" 2>/dev/null \
    | grep -oP '"browser_download_url":\s*"\K[^"]+\.apk' | head -1) || true

if [[ -n "$PROTON_APK_URL" ]]; then
    install_apk "ch.protonmail.android" "Proton Mail" "$PROTON_APK_URL"
else
    # Fallback: fetch release tag and construct URL
    PROTON_TAG=$(curl -fsSL "https://api.github.com/repos/ProtonMail/android-mail/releases/latest" 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1) || true

    if [[ -n "$PROTON_TAG" ]]; then
        log_info "No APK in GitHub release assets. Trying tag: $PROTON_TAG"
        log_warn "Proton Mail may need manual install from Aurora Store."
        printf "  %-20s " "Proton Mail"
        echo -e "${YELLOW}no APK in release — install from Aurora Store${NC}"
        FAILED+=("Proton Mail (no APK asset)")
    else
        printf "  %-20s " "Proton Mail"
        echo -e "${RED}could not fetch release info${NC}"
        FAILED+=("Proton Mail")
    fi
fi

# --- Summary ---

echo ""
if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    log_ok "Installed: ${INSTALLED[*]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_warn "Failed: ${FAILED[*]}"
    echo ""
    echo "For failed apps, open Aurora Store on the device and search for them."
fi

echo ""
log_info "Aurora Store will handle future updates for these apps."
