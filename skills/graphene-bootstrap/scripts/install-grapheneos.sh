#!/usr/bin/env bash
# install-grapheneos.sh — Install GrapheneOS on a connected Pixel phone
#
# Runs from the computer connected to the Pixel via USB.
# Detects the device, downloads the latest stable GrapheneOS image,
# verifies its signature, flashes it, and locks the bootloader.
#
# Requirements:
#   - fastboot 35.0.1+ and adb in PATH
#   - curl, ssh-keygen on this machine
#   - bsdtar or unzip for extraction
#   - Pixel phone connected via USB with OEM unlocking enabled
#
# Usage:
#   bash install-grapheneos.sh              # full install
#   bash install-grapheneos.sh --dry-run    # show what would happen
#
# WARNING: This script WIPES ALL DATA on the device (twice: unlock + lock).

set -euo pipefail

# --- Config ---

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RELEASES_URL="https://releases.grapheneos.org"
SIGNING_KEY="contact@grapheneos.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIUg/m5CoP83b0rfSCzYSVA4cw4ir49io5GPoxbgxdJE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Device codename → friendly name
declare -A DEVICE_NAMES=(
    [stallion]="Pixel 10a"
    [rango]="Pixel 10 Pro Fold"
    [mustang]="Pixel 10 Pro XL"
    [blazer]="Pixel 10 Pro"
    [frankel]="Pixel 10"
    [tegu]="Pixel 9a"
    [comet]="Pixel 9 Pro Fold"
    [komodo]="Pixel 9 Pro XL"
    [caiman]="Pixel 9 Pro"
    [tokay]="Pixel 9"
    [akita]="Pixel 8a"
    [husky]="Pixel 8 Pro"
    [shiba]="Pixel 8"
    [felix]="Pixel Fold"
    [tangorpro]="Pixel Tablet"
    [lynx]="Pixel 7a"
    [cheetah]="Pixel 7 Pro"
    [panther]="Pixel 7"
    [bluejay]="Pixel 6a"
    [raven]="Pixel 6 Pro"
    [oriole]="Pixel 6"
)

# --- Helpers ---

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
log_step()  { echo -e "\n${CYAN}=== $* ===${NC}"; }

confirm() {
    local msg="$1"
    echo ""
    echo -e "${YELLOW}${msg}${NC}"
    read -r -p "Type YES to continue: " answer
    if [[ "$answer" != "YES" ]]; then
        echo "Aborted."
        exit 0
    fi
}

# --- Temp directory ---

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Phase 0: Prerequisites ---

check_deps() {
    log_step "Phase 0: Prerequisites"

    local missing=()
    for cmd in fastboot curl ssh-keygen; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    # adb is optional (used to reboot into bootloader)
    if ! command -v adb &>/dev/null; then
        log_warn "adb not found — device must already be in fastboot mode"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fail "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check fastboot version
    local fb_version
    fb_version=$(fastboot --version 2>&1 | head -1)
    log_info "fastboot: $fb_version"

    local fb_ver_num
    fb_ver_num=$(echo "$fb_version" | grep -oP '\d+\.\d+\.\d+' | head -1) || true
    if [[ -n "$fb_ver_num" ]]; then
        local major minor patch
        IFS='.' read -r major minor patch <<< "$fb_ver_num"
        if (( major < 35 || (major == 35 && minor == 0 && patch < 1) )); then
            log_fail "fastboot 35.0.1+ required, found $fb_ver_num"
            log_info "Download from: https://dl.google.com/android/repository/platform-tools_r35.0.2-linux.zip"
            exit 1
        fi
    fi

    # Check for extraction tool
    if command -v bsdtar &>/dev/null; then
        EXTRACT_CMD="bsdtar"
    elif command -v unzip &>/dev/null; then
        EXTRACT_CMD="unzip"
    else
        log_fail "bsdtar or unzip required for extraction"
        exit 1
    fi

    log_ok "All tools found (extraction: $EXTRACT_CMD)"
}

# --- Phase 1: Connect to device in fastboot mode ---

connect_device() {
    log_step "Phase 1: Connect to Device"

    # Check if already in fastboot mode
    local fb_devices
    fb_devices=$(fastboot devices 2>/dev/null | grep -c 'fastboot') || true

    if [[ "$fb_devices" -ge 1 ]]; then
        log_ok "Device detected in fastboot mode"
    elif command -v adb &>/dev/null; then
        # Try ADB
        local adb_devices
        adb_devices=$(adb devices 2>/dev/null | grep -cE '\tdevice$') || true

        if [[ "$adb_devices" -eq 0 ]]; then
            log_fail "No device found via fastboot or ADB."
            echo "Either:"
            echo "  1. Boot into fastboot mode (hold Volume Down + Power), or"
            echo "  2. Enable USB debugging and connect via ADB"
            exit 1
        fi

        if [[ "$adb_devices" -gt 1 ]]; then
            log_fail "Multiple ADB devices found. Connect only one."
            exit 1
        fi

        log_info "Device found via ADB. Rebooting into bootloader..."
        adb reboot bootloader
        sleep 5

        # Wait for fastboot device (up to 30s)
        local waited=0
        while [[ $waited -lt 30 ]]; do
            fb_devices=$(fastboot devices 2>/dev/null | grep -c 'fastboot') || true
            [[ "$fb_devices" -ge 1 ]] && break
            sleep 2
            waited=$((waited + 2))
        done

        if [[ "$fb_devices" -eq 0 ]]; then
            log_fail "Device did not appear in fastboot mode after reboot."
            exit 1
        fi
        log_ok "Device rebooted into fastboot mode"
    else
        log_fail "No device found. Boot into fastboot mode manually (hold Volume Down + Power)."
        exit 1
    fi

    # Detect device codename
    DEVICE_CODENAME=$(fastboot getvar product 2>&1 | grep 'product:' | awk '{print $2}') || true
    if [[ -z "$DEVICE_CODENAME" ]]; then
        log_fail "Could not detect device codename via fastboot."
        exit 1
    fi

    DEVICE_FRIENDLY="${DEVICE_NAMES[$DEVICE_CODENAME]:-Unknown ($DEVICE_CODENAME)}"
    log_ok "Detected: $DEVICE_FRIENDLY (codename: $DEVICE_CODENAME)"

    if [[ -z "${DEVICE_NAMES[$DEVICE_CODENAME]:-}" ]]; then
        log_fail "Device '$DEVICE_CODENAME' is not supported by GrapheneOS."
        echo "Supported devices:"
        for code in $(printf '%s\n' "${!DEVICE_NAMES[@]}" | sort); do
            echo "  $code — ${DEVICE_NAMES[$code]}"
        done
        exit 1
    fi
}

# --- Phase 2: Fetch latest version ---

fetch_version() {
    log_step "Phase 2: Fetch Latest Stable Version"

    local channel_url="${RELEASES_URL}/${DEVICE_CODENAME}-stable"
    local channel_info
    channel_info=$(curl -fsSL "$channel_url" 2>/dev/null) || {
        log_fail "Could not fetch version info from $channel_url"
        exit 1
    }

    VERSION=$(echo "$channel_info" | awk '{print $1}')
    if [[ -z "$VERSION" ]]; then
        log_fail "Could not parse version from channel file."
        exit 1
    fi

    log_ok "Latest stable version: $VERSION"

    IMAGE_ZIP="${DEVICE_CODENAME}-install-${VERSION}.zip"
    IMAGE_SIG="${IMAGE_ZIP}.sig"
    IMAGE_URL="${RELEASES_URL}/${IMAGE_ZIP}"
    SIG_URL="${RELEASES_URL}/${IMAGE_SIG}"

    log_info "Image: $IMAGE_ZIP"
}

# --- Phase 3: Download and verify ---

download_and_verify() {
    log_step "Phase 3: Download and Verify Image"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would download:"
        log_info "  $IMAGE_URL"
        log_info "  $SIG_URL"
        return
    fi

    cd "$TMPDIR"

    # Write allowed_signers
    echo "$SIGNING_KEY" > allowed_signers

    # Download image
    if [[ -f "$IMAGE_ZIP" ]]; then
        log_info "Image already downloaded, skipping"
    else
        log_info "Downloading $IMAGE_ZIP (this may take a while)..."
        curl -f --progress-bar -O "$IMAGE_URL" || {
            log_fail "Download failed: $IMAGE_URL"
            exit 1
        }
    fi

    # Download signature
    log_info "Downloading signature..."
    curl -fsSL -O "$SIG_URL" || {
        log_fail "Signature download failed: $SIG_URL"
        exit 1
    }

    # Verify signature
    log_info "Verifying signature..."
    if ssh-keygen -Y verify -f allowed_signers -I contact@grapheneos.org \
        -n "factory images" -s "$IMAGE_SIG" < "$IMAGE_ZIP" 2>/dev/null; then
        log_ok "Signature verified successfully"
    else
        log_fail "SIGNATURE VERIFICATION FAILED — image may be corrupted or tampered with."
        log_fail "Delete the downloaded files and try again."
        exit 1
    fi
}

# --- Phase 4: Extract ---

extract_image() {
    log_step "Phase 4: Extract Image"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would extract $IMAGE_ZIP"
        return
    fi

    cd "$TMPDIR"

    log_info "Extracting $IMAGE_ZIP..."
    case "$EXTRACT_CMD" in
        bsdtar)
            bsdtar xvf "$IMAGE_ZIP"
            ;;
        unzip)
            unzip -o "$IMAGE_ZIP"
            ;;
    esac

    IMAGE_DIR="${DEVICE_CODENAME}-install-${VERSION}"
    if [[ ! -d "$IMAGE_DIR" ]]; then
        # Try factory naming as fallback
        IMAGE_DIR="${DEVICE_CODENAME}-factory-${VERSION}"
    fi

    if [[ ! -d "$IMAGE_DIR" ]]; then
        log_fail "Expected directory not found after extraction."
        ls -la
        exit 1
    fi

    if [[ ! -f "$IMAGE_DIR/flash-all.sh" ]]; then
        log_fail "flash-all.sh not found in $IMAGE_DIR"
        exit 1
    fi

    log_ok "Extracted to $IMAGE_DIR"
}

# --- Phase 5: Unlock bootloader ---

unlock_bootloader() {
    log_step "Phase 5: Unlock Bootloader"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would unlock bootloader"
        return
    fi

    # Check current lock state
    local lock_state
    lock_state=$(fastboot getvar unlocked 2>&1 | grep 'unlocked:' | awk '{print $2}') || true

    if [[ "$lock_state" == "yes" ]]; then
        log_ok "Bootloader already unlocked"
        return
    fi

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  WARNING: Unlocking the bootloader WIPES ALL DEVICE DATA   ║${NC}"
    echo -e "${RED}║  Back up anything important before proceeding.              ║${NC}"
    echo -e "${RED}║                                                             ║${NC}"
    echo -e "${RED}║  OEM unlocking must be enabled in Developer Options.        ║${NC}"
    echo -e "${RED}║  Carrier-locked devices cannot be unlocked.                 ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

    confirm "Unlock bootloader and WIPE ALL DATA?"

    log_info "Unlocking bootloader..."
    fastboot flashing unlock

    echo ""
    log_warn ">>> ON YOUR PHONE: Use Volume buttons to select 'Unlock the bootloader', then press Power to confirm <<<"
    read -r -p "Press Enter here once confirmed on device..."

    # Wait for device to reappear
    sleep 5
    local waited=0
    while [[ $waited -lt 30 ]]; do
        local fb_count
        fb_count=$(fastboot devices 2>/dev/null | grep -c 'fastboot') || true
        [[ "$fb_count" -ge 1 ]] && break
        sleep 2
        waited=$((waited + 2))
    done

    log_ok "Bootloader unlocked"
}

# --- Phase 6: Flash ---

flash_image() {
    log_step "Phase 6: Flash GrapheneOS"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would run flash-all.sh in $IMAGE_DIR"
        return
    fi

    cd "$TMPDIR/$IMAGE_DIR"

    echo ""
    echo -e "${YELLOW}Flashing GrapheneOS ${VERSION} to ${DEVICE_FRIENDLY}...${NC}"
    echo -e "${YELLOW}DO NOT disconnect the device or press any buttons until complete.${NC}"
    echo -e "${YELLOW}The device will reboot multiple times automatically.${NC}"
    echo ""

    # Ensure enough tmp space
    mkdir -p "$TMPDIR/flashtmp"
    TMPDIR="$TMPDIR/flashtmp" bash flash-all.sh

    log_ok "Flashing complete"
}

# --- Phase 7: Lock bootloader ---

lock_bootloader() {
    log_step "Phase 7: Lock Bootloader"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would lock bootloader"
        return
    fi

    # Wait for device in fastboot mode
    log_info "Waiting for device in fastboot mode..."
    local waited=0
    while [[ $waited -lt 60 ]]; do
        local fb_count
        fb_count=$(fastboot devices 2>/dev/null | grep -c 'fastboot') || true
        [[ "$fb_count" -ge 1 ]] && break
        sleep 2
        waited=$((waited + 2))
    done

    if [[ $waited -ge 60 ]]; then
        log_warn "Device not detected in fastboot mode."
        log_warn "If the device booted to the OS, reboot to bootloader manually"
        log_warn "(hold Volume Down during reboot) and run: fastboot flashing lock"
        return
    fi

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Locking the bootloader enables verified boot (essential    ║${NC}"
    echo -e "${RED}║  for security) and WIPES DATA again for tamper protection.  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

    confirm "Lock bootloader? (STRONGLY recommended)"

    log_info "Locking bootloader..."
    fastboot flashing lock

    echo ""
    log_warn ">>> ON YOUR PHONE: Use Volume buttons to select 'Lock the bootloader', then press Power to confirm <<<"
    read -r -p "Press Enter here once confirmed on device..."

    log_ok "Bootloader locked"
}

# --- Phase 8: Summary ---

print_summary() {
    log_step "Installation Complete"

    echo ""
    echo -e "${GREEN}GrapheneOS ${VERSION} has been installed on your ${DEVICE_FRIENDLY}.${NC}"
    echo ""
    echo -e "${CYAN}--- Post-install steps ---${NC}"
    echo "1. Press Power to boot with 'Start' selected"
    echo "2. During initial setup, UNCHECK 'OEM unlocking' on the final screen"
    echo "3. Complete the GrapheneOS setup wizard"
    echo "4. Then run: bash setup-android-apps.sh   (to install all your apps)"
    echo ""
    echo -e "${CYAN}--- Verified boot ---${NC}"
    echo "On 6th gen+ Pixels, a yellow notice with a key fingerprint is normal."
    echo "This confirms GrapheneOS verified boot is active."
    echo "Compare against: https://grapheneos.org/install/cli#verified-boot"
}

# --- Main ---

main() {
    echo -e "${CYAN}=== GrapheneOS Installer ===${NC}"
    echo "Timestamp: $(date -Iseconds)"
    $DRY_RUN && echo -e "${YELLOW}DRY RUN MODE — no changes will be made${NC}"
    echo ""

    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  This script will ERASE ALL DATA on your device and         ║${NC}"
    echo -e "${RED}║  install GrapheneOS. Make sure you have backups.            ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

    if ! $DRY_RUN; then
        confirm "Proceed with GrapheneOS installation?"
    fi

    check_deps
    connect_device
    fetch_version
    download_and_verify
    extract_image
    unlock_bootloader
    flash_image
    lock_bootloader
    print_summary
}

main
