#!/usr/bin/env bash
# setup-android-apps.sh — Install F-Droid, repos, and all apps via ADB
#
# Runs from the computer connected to the Android device via ADB.
# Downloads F-Droid repo indices, extracts latest APKs, and installs
# all apps required by the sing-box per-app Tor isolation config.
#
# Requirements:
#   - adb connected to device (adb devices shows it)
#   - curl, jq, unzip on this machine
#   - Device has USB debugging enabled
#
# Usage:
#   bash setup-android-apps.sh              # full install
#   bash setup-android-apps.sh --dry-run    # show what would be installed

set -euo pipefail

# --- Config ---

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FDROID_APK_URL="https://f-droid.org/F-Droid.apk"

# Custom F-Droid repos: name|url|fingerprint
CUSTOM_REPOS=(
    "IzzyOnDroid|https://apt.izzysoft.de/fdroid/repo|3BF0D6ABFEAE2F401707B6D966BE743BF0EEE49C2561B9BA39073711F628937A"
    "Guardian Project|https://guardianproject.info/fdroid/repo|B7C2EEFD8DAC7806AF67DFCD92EB18126BC08312A7F2D6F3862E46013C7A6135"
    "Threema|https://releases.threema.ch/fdroid/repo|5734E753899B25775D90FE85362A49866E05AC4F83C05BEF5A92880D2910639E"
    "SchildiChat|https://s2.spiritcroc.de/fdroid/repo|6612ADE7E93174A589CF5BA26ED3AB28231A789640546C8F30375EF045BC9242"
    "Brave|https://brave-browser-apk-release.s3.brave.com/fdroid/repo|3C60DE135AA19EC949E998469C908F7171885C1E2805F39EB403DDB0F37B4BD2"
    "Session|https://fdroid.getsession.org/fdroid/repo|DB0E5297EB65CC22D6BD93C869943BDCFCB6A07DC69A48A0DD8C7BA698EC04E6"
    "Monerujo|https://f-droid.monerujo.io/fdroid/repo|A82C68E14AF0AA6A2EC20E6B272EFF25E5A038F3F65884316E0F5E0D91E7B713"
    "Cake Labs|https://fdroid.cakelabs.com/repo|EA44EFAEE0B641EE7A032D397D5D976F9C4E5E1ED26E11C75702D064E55F8755"
    "Stack Wallet|https://fdroid.stackwallet.com/fdroid/repo|764B4262F75750A5F620A205CEE2886F18635FBDA18DF40758F5A1A45A950F84"
)

# Apps from F-Droid main repo: package|friendly_name
FDROID_MAIN_APPS=(
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
)

# Apps from custom repos: package|friendly_name|repo_name
CUSTOM_REPO_APPS=(
    "com.brave.browser|Brave Browser|Brave"
    "ch.threema.app.libre|Threema Libre|Threema"
    "network.loki.messenger|Session|Session"
    "org.torproject.android|Orbot|Guardian Project"
    "chat.schildi.android|SchildiChat Next|SchildiChat"
    "org.maintainteam.hypatia|Hypatia (maintained)|IzzyOnDroid"
    "org.torproject.torbrowser|Tor Browser|Guardian Project"
    "com.m2049r.xmrwallet|Monerujo|Monerujo"
    "com.cakewallet.cake_wallet|Cake Wallet|Cake Labs"
    "com.monero.app|Monero.com|Cake Labs"
    "com.cypherstack.stackwallet|Stack Wallet|Stack Wallet"
)

# Battery optimization whitelist
BATTERY_WHITELIST=(
    "org.torproject.android"
    "io.nekohasekai.sfa"
)

# --- State tracking ---

INSTALLED=()
SKIPPED=()
FAILED=()

# --- Helpers ---

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
log_step()  { echo -e "\n${CYAN}=== $* ===${NC}"; }

# --- Phase 0: Prerequisites ---

check_deps() {
    log_step "Phase 0: Prerequisites"
    local missing=()
    for cmd in adb curl jq unzip; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fail "Missing required tools: ${missing[*]}"
        echo "Install them and re-run."
        exit 1
    fi
    log_ok "All tools found: adb, curl, jq, unzip"
}

check_device() {
    local device_count
    device_count=$(adb devices 2>/dev/null | grep -cE '\tdevice$') || true
    if [[ "$device_count" -eq 0 ]]; then
        log_fail "No ADB device connected. Enable USB debugging and authorize this computer."
        exit 1
    elif [[ "$device_count" -gt 1 ]]; then
        log_fail "Multiple ADB devices found. Connect only one device."
        exit 1
    fi

    local model brand android
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    android=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    DEVICE_ARCH=$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')

    log_ok "Device: $brand $model (Android $android, arch: $DEVICE_ARCH)"

    # Cache installed packages
    mapfile -t INSTALLED_PKGS < <(adb shell pm list packages 2>/dev/null | sed 's/package://' | tr -d '\r')
    log_info "Found ${#INSTALLED_PKGS[@]} installed packages"
}

is_installed() {
    local pkg="$1"
    for p in "${INSTALLED_PKGS[@]}"; do
        [[ "$p" == "$pkg" ]] && return 0
    done
    return 1
}

# --- Temp directory ---

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Phase 1: Bootstrap F-Droid ---

install_fdroid() {
    log_step "Phase 1: Bootstrap F-Droid"

    if is_installed "org.fdroid.fdroid"; then
        log_warn "F-Droid already installed, skipping"
        SKIPPED+=("org.fdroid.fdroid|F-Droid")
        return
    fi

    log_info "Downloading F-Droid APK..."
    if $DRY_RUN; then
        log_info "[DRY RUN] Would download $FDROID_APK_URL and install"
        return
    fi

    local apk="$TMPDIR/F-Droid.apk"
    if curl -fSL -o "$apk" "$FDROID_APK_URL"; then
        if adb install -r "$apk" 2>/dev/null; then
            log_ok "F-Droid installed"
            INSTALLED+=("org.fdroid.fdroid|F-Droid")
        else
            log_fail "F-Droid install failed"
            FAILED+=("org.fdroid.fdroid|F-Droid")
        fi
    else
        log_fail "F-Droid download failed"
        FAILED+=("org.fdroid.fdroid|F-Droid")
    fi
}

# --- Phase 2: Add Custom Repos ---

add_repos() {
    log_step "Phase 2: Add Custom F-Droid Repos"

    for entry in "${CUSTOM_REPOS[@]}"; do
        IFS='|' read -r name url fingerprint <<< "$entry"
        # Convert https:// to fdroidrepos://
        local intent_url="fdroidrepos://${url#https://}?fingerprint=$fingerprint"

        log_info "Adding repo: $name"
        if $DRY_RUN; then
            log_info "[DRY RUN] Would open: $intent_url"
            continue
        fi

        adb shell am start -a android.intent.action.VIEW -d "'$intent_url'" >/dev/null 2>&1 || {
            log_warn "Failed to send intent for $name — add manually"
        }
        sleep 2
    done

    if ! $DRY_RUN; then
        echo ""
        log_warn ">>> CHECK YOUR PHONE <<<"
        log_warn "Confirm each repo addition in F-Droid, then press Enter here to continue."
        read -r -p ""
    fi
}

# --- Phase 3: Install Apps from Repos ---

# Download and cache a repo's index-v1.json
# Sets INDEX_JSON to the extracted file path, REPO_ADDRESS to the base URL
fetch_repo_index() {
    local repo_url="$1"
    local cache_key
    cache_key=$(echo "$repo_url" | md5sum | cut -d' ' -f1)
    local index_dir="$TMPDIR/index_$cache_key"
    INDEX_JSON="$index_dir/index-v1.json"
    REPO_ADDRESS=""

    if [[ -f "$INDEX_JSON" ]]; then
        REPO_ADDRESS=$(jq -r '.repo.address // empty' "$INDEX_JSON")
        return 0
    fi

    mkdir -p "$index_dir"
    local jar="$index_dir/index-v1.jar"

    log_info "  Fetching index from ${repo_url}..."
    if ! curl -fSL -o "$jar" "${repo_url}/index-v1.jar" 2>/dev/null; then
        log_fail "  Failed to download index from ${repo_url}"
        return 1
    fi

    if ! unzip -o -q "$jar" index-v1.json -d "$index_dir" 2>/dev/null; then
        log_fail "  Failed to extract index-v1.json"
        return 1
    fi

    REPO_ADDRESS=$(jq -r '.repo.address // empty' "$INDEX_JSON")
    if [[ -z "$REPO_ADDRESS" ]]; then
        log_fail "  No repo.address found in index"
        return 1
    fi
    return 0
}

# Find the latest APK name for a package from an index
find_latest_apk() {
    local index_json="$1"
    local pkg="$2"

    jq -r --arg pkg "$pkg" '
        .packages[$pkg] // empty
        | sort_by(.versionCode)
        | last
        | .apkName // empty
    ' "$index_json"
}

# Download APK and install via ADB
install_from_repo() {
    local pkg="$1"
    local name="$2"
    local repo_url="$3"

    printf "  %-25s " "$name"

    if is_installed "$pkg"; then
        echo -e "${YELLOW}already installed${NC}"
        SKIPPED+=("$pkg|$name")
        return
    fi

    if $DRY_RUN; then
        echo -e "${CYAN}[DRY RUN] would install from ${repo_url}${NC}"
        return
    fi

    if ! fetch_repo_index "$repo_url"; then
        echo -e "${RED}index fetch failed${NC}"
        FAILED+=("$pkg|$name")
        return
    fi

    local apk_name
    apk_name=$(find_latest_apk "$INDEX_JSON" "$pkg")
    if [[ -z "$apk_name" ]]; then
        echo -e "${RED}not found in repo${NC}"
        FAILED+=("$pkg|$name")
        return
    fi

    local apk_url="${REPO_ADDRESS}/${apk_name}"
    local apk_file="$TMPDIR/$apk_name"

    if ! curl -fSL -o "$apk_file" "$apk_url" 2>/dev/null; then
        echo -e "${RED}download failed${NC}"
        FAILED+=("$pkg|$name")
        return
    fi

    if adb install -r "$apk_file" >/dev/null 2>&1; then
        echo -e "${GREEN}installed${NC}"
        INSTALLED+=("$pkg|$name")
    else
        echo -e "${RED}adb install failed${NC}"
        FAILED+=("$pkg|$name")
    fi

    rm -f "$apk_file"
}

install_main_repo_apps() {
    log_step "Phase 3: Install Apps from F-Droid Main Repo"
    local repo_url="https://f-droid.org/repo"

    for entry in "${FDROID_MAIN_APPS[@]}"; do
        IFS='|' read -r pkg name <<< "$entry"
        install_from_repo "$pkg" "$name" "$repo_url"
    done
}

install_custom_repo_apps() {
    log_step "Phase 4: Install Apps from Custom Repos"

    for entry in "${CUSTOM_REPO_APPS[@]}"; do
        IFS='|' read -r pkg name repo_name <<< "$entry"

        # Find the repo URL for this app
        local repo_url=""
        for repo_entry in "${CUSTOM_REPOS[@]}"; do
            IFS='|' read -r rname rurl _rfp <<< "$repo_entry"
            if [[ "$rname" == "$repo_name" ]]; then
                repo_url="$rurl"
                break
            fi
        done

        if [[ -z "$repo_url" ]]; then
            printf "  %-25s " "$name"
            echo -e "${RED}repo '$repo_name' not found in config${NC}"
            FAILED+=("$pkg|$name")
            continue
        fi

        install_from_repo "$pkg" "$name" "$repo_url"
    done
}

# --- Phase 5: Post-Install ---

post_install() {
    log_step "Phase 5: Post-Install Configuration"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would push singbox-config.json and whitelist battery optimization"
        return
    fi

    # Push sing-box config to device
    local config_dir
    config_dir="$(cd "$(dirname "$0")" && pwd)"
    local config_file="$config_dir/singbox-config.json"

    if [[ -f "$config_file" ]]; then
        if adb push "$config_file" /sdcard/Download/singbox-config.json >/dev/null 2>&1; then
            log_ok "Pushed singbox-config.json to /sdcard/Download/"
        else
            log_warn "Failed to push singbox-config.json"
        fi
    fi

    # Battery optimization whitelist
    for pkg in "${BATTERY_WHITELIST[@]}"; do
        adb shell dumpsys deviceidle whitelist "+$pkg" >/dev/null 2>&1 || true
        log_ok "Battery whitelist: $pkg"
    done
}

# --- Phase 6: Summary ---

print_summary() {
    log_step "Summary"

    echo ""
    echo "Installed:  ${#INSTALLED[@]}"
    for entry in "${INSTALLED[@]}"; do
        IFS='|' read -r pkg name <<< "$entry"
        echo -e "  ${GREEN}+${NC} $name ($pkg)"
    done

    if [[ ${#SKIPPED[@]} -gt 0 ]]; then
        echo ""
        echo "Skipped (already installed):  ${#SKIPPED[@]}"
        for entry in "${SKIPPED[@]}"; do
            IFS='|' read -r pkg name <<< "$entry"
            echo -e "  ${YELLOW}-${NC} $name ($pkg)"
        done
    fi

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo ""
        echo "Failed:  ${#FAILED[@]}"
        for entry in "${FAILED[@]}"; do
            IFS='|' read -r pkg name <<< "$entry"
            echo -e "  ${RED}!${NC} $name ($pkg)"
        done
    fi

    echo ""
    echo -e "${CYAN}--- Manual steps remaining ---${NC}"
    echo "1. Open Aurora Store → sign in → install Proton Mail (ch.protonmail.android)"
    echo "2. Open F-Droid → verify all repos were added (Settings → Repositories)"
    echo "3. Import sing-box config from /sdcard/Download/singbox-config.json"
    echo "4. Set sing-box (SFA) as always-on VPN (Settings → Network → VPN)"
    echo "5. Configure Orbot with custom torrc (see orbot-custom-torrc.conf)"
    echo "6. Run: bash verify-tor-isolation.sh"
    echo ""

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Some apps failed to install. Re-run the script to retry (safe to re-run).${NC}"
    else
        echo -e "${GREEN}All apps installed successfully.${NC}"
    fi
}

# --- Main ---

main() {
    echo -e "${CYAN}=== Android App Setup via ADB ===${NC}"
    echo "Timestamp: $(date -Iseconds)"
    $DRY_RUN && echo -e "${YELLOW}DRY RUN MODE — no changes will be made${NC}"
    echo ""

    check_deps
    check_device
    install_fdroid
    add_repos
    install_main_repo_apps
    install_custom_repo_apps
    post_install
    print_summary
}

main
