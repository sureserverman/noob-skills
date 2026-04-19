---
name: graphene-bootstrap
description: Use when the user mentions installing GrapheneOS, flashing a Pixel, wiping a Pixel, reinstalling their mobile OS, setting up F-Droid, configuring Orbot or sing-box, or preparing a phone for per-app Tor isolation. Also trigger on "set up my phone", "new phone", "flash my pixel", or any Pixel reflash/setup request.
---

# Android Phone Setup

This skill guides through two phases of setting up a privacy-focused Pixel phone:

1. **Install GrapheneOS** — wipe the phone and flash GrapheneOS via fastboot
2. **Install Apps** — install F-Droid, custom repos, and all apps for per-app Tor isolation via ADB

Each phase has a dedicated script. The canonical copies live in `docs/android/` and are also bundled with this skill at `.claude/skills/graphene-bootstrap/scripts/`. Both locations contain the same scripts — use whichever is reachable from the working directory.

## Scripts

| Script | Purpose | Device state |
|--------|---------|-------------|
| `install-grapheneos.sh` | Flash GrapheneOS on a Pixel | Phone in fastboot or ADB mode |
| `setup-android-apps.sh` | Install F-Droid, repos, and 16 apps | GrapheneOS booted, USB debugging on |
| `install-aurora-apps.sh` | Install Telegram and Proton Mail | GrapheneOS booted, USB debugging on |
| `verify-setup.sh` | Verify entire setup is correct | GrapheneOS booted, USB debugging on |
| `singbox-config.json` | Per-app Tor routing config for sing-box | Pushed to device by `setup-android-apps.sh` |

Paths (use whichever resolves):
- `docs/android/` (project)
- `.claude/skills/graphene-bootstrap/scripts/` (bundled with skill)

## Decision Flow

Ask the user where they are in the process:

**"Does the phone already have GrapheneOS installed?"**

- **No / Fresh phone / Want to reinstall** → Start with Phase 1 (GrapheneOS install), then Phase 2 (apps)
- **Yes, GrapheneOS is installed** → Skip to Phase 2 (apps only)
- **Just need to reflash / something broke** → Phase 1 only

## Phase 1: Install GrapheneOS

### Before Running

Walk through these prerequisites with the user:

1. **Device**: Must be a supported Google Pixel (6 through 10 series). Ask which model they have.
2. **USB cable**: Use the cable that came with the phone. Avoid USB hubs.
3. **OEM unlocking**: Must be enabled on the device first:
   - Settings > About phone > tap Build number 7 times
   - Settings > System > Developer options > enable OEM unlocking
   - This requires internet on some carrier variants
4. **Tools on computer**: `fastboot` 35.0.1+, `curl`, `ssh-keygen`, `bsdtar` or `unzip`
   - On Ubuntu/Debian: `sudo apt install libarchive-tools openssh-client android-sdk-platform-tools-common`
   - Then download standalone platform-tools (distro fastboot packages are broken):
     ```
     curl -O https://dl.google.com/android/repository/platform-tools_r35.0.2-linux.zip
     echo 'acfdcccb123a8718c46c46c059b2f621140194e5ec1ac9d81715be3d6ab6cd0a  platform-tools_r35.0.2-linux.zip' | sha256sum -c
     bsdtar xvf platform-tools_r35.0.2-linux.zip
     export PATH="$PWD/platform-tools:$PATH"
     ```
   - On Arch: `sudo pacman -S android-tools android-udev openssh`
5. **Backup**: The phone will be wiped TWICE (unlock + lock bootloader). Confirm user has backed up.
6. **Linux workaround**: Stop fwupd if running — `sudo systemctl stop fwupd.service`

### Running the Script

```bash
# Preview what will happen
bash docs/android/install-grapheneos.sh --dry-run

# Full install
bash docs/android/install-grapheneos.sh
```

The script handles: device detection, image download, signature verification, bootloader unlock, flashing, and bootloader re-lock. It pauses for user confirmation before destructive steps.

### Troubleshooting Phase 1

| Problem | Cause | Fix |
|---------|-------|-----|
| `fastboot: command not found` | Not in PATH | Re-run the `export PATH=...` line above |
| `fastboot` version too old | Distro package is outdated | Download standalone platform-tools (see above) |
| `No device found` | USB issue or not in fastboot mode | Try a different cable/port; hold Volume Down + Power to enter fastboot |
| `FAILED (remote: 'oem unlock is not allowed')` | OEM unlocking not enabled | Enable in Developer options (requires internet) |
| `FAILED (remote: 'flashing unlock is not allowed')` | Carrier-locked device | Carrier variants cannot be unlocked — need an unlocked Pixel |
| Device disappears during flash | USB connection dropped | Use the original cable, direct port, no hubs. Re-run script. |
| Signature verification failed | Corrupted download | Delete the zip and re-run — script will re-download |

## Phase 2: Install Apps

### Before Running

1. **GrapheneOS booted**: Complete the initial setup wizard first
2. **USB debugging**: Enable it:
   - Settings > About phone > tap Build number 7 times
   - Settings > System > Developer options > enable USB debugging
   - Connect USB, authorize the computer on the phone prompt
3. **Tools on computer**: `adb`, `curl`, `jq`, `unzip`
   - On Ubuntu/Debian: `sudo apt install android-tools-adb jq unzip`
   - On Arch: `sudo pacman -S android-tools jq unzip`
4. **Verify connection**: Run `adb devices` — should show the device

### Running the Script

```bash
# Preview what will happen
bash docs/android/setup-android-apps.sh --dry-run

# Full install
bash docs/android/setup-android-apps.sh
```

The script will:
1. Install F-Droid via ADB
2. Add 9 custom F-Droid repos (user confirms each on phone)
3. Download and install 23 apps from repo indices
5. Push sing-box config to device
6. Whitelist Orbot and sing-box from battery optimization

### What Gets Installed

**From F-Droid main repo (12):** Firefox, Conversations, Element X, FluffyChat, aTalk, SimpleX Chat, Tuta Mail, sing-box SFA, Auditor, Aurora Store, Faraday, TRIfA

**From custom repos (11):** Brave (Brave repo), Threema Libre (Threema repo), Session (Session repo), Orbot (Guardian Project repo), Tor Browser (Guardian Project repo), SchildiChat Next (SchildiChat repo), Hypatia (IzzyOnDroid repo), Monerujo (Monerujo repo), Cake Wallet (Cake Labs repo), Monero.com (Cake Labs repo), Stack Wallet (Stack Wallet repo)

### After the Script

These steps must be done manually on the phone:

1. Open F-Droid > Settings > Repositories — verify all 9 custom repos are added
3. Open sing-box (SFA) > import config from `/sdcard/Download/singbox-config.json`
4. Settings > Network > VPN > set sing-box as always-on VPN
5. Open Orbot > paste custom torrc from `docs/android/orbot-custom-torrc.conf`
6. Verify isolation: `bash docs/android/verify-tor-isolation.sh`

### Troubleshooting Phase 2

| Problem | Cause | Fix |
|---------|-------|-----|
| `No ADB device connected` | USB debugging off or not authorized | Enable USB debugging; re-plug and tap "Allow" on phone |
| `jq: command not found` | Missing dependency | Install jq: `sudo apt install jq` or `sudo pacman -S jq` |
| Index download fails for a repo | Network issue or repo down | Re-run the script — it skips already-installed apps |
| App shows "not found in repo" | Package removed or renamed | Check if the app moved to a different repo; install manually from F-Droid |
| `adb install` fails | Conflicting signatures | Uninstall the old version first: `adb uninstall <package>` |
| F-Droid repo intent doesn't open | F-Droid not installed yet | Make sure Phase 1 of the script completed (F-Droid install) |

## Phase 3: Install Aurora Store Apps (Telegram, Proton Mail)

Apps not on F-Droid are downloaded as official APKs and sideloaded via ADB. Aurora Store handles future updates.

### Running the Script

```bash
bash docs/android/install-aurora-apps.sh
```

The script downloads:
- **Telegram** from `telegram.org` (also has built-in updater)
- **Proton Mail** from GitHub releases (`ProtonMail/android-mail`)

If the Proton Mail APK isn't in the GitHub release assets, the script tells you to install it from Aurora Store manually.

## Phase 4: Verify Setup

After all phases are complete, run the verification script to confirm everything is installed and configured correctly.

### Running the Script

```bash
bash docs/android/verify-setup.sh
```

The script checks:
- **App installation**: All 24 F-Droid apps, 2 Aurora Store apps, 2 system apps
- **Running services**: Orbot and sing-box SFA are running
- **VPN status**: sing-box is set as always-on VPN with lockdown enabled
- **Battery optimization**: Orbot and sing-box are whitelisted
- **sing-box config**: Config file present or already imported
- **Orbot ports**: 16+ SOCKS ports listening (per-app isolation) + DNSPort 5400
- **Security**: OEM unlocking disabled, USB debugging warning

Each check reports PASS, FAIL, or WARN. The summary at the end shows counts and common fixes for any failures.

## Related Files

| File | Purpose |
|------|---------|
| `docs/android/singbox-config.json` | Per-app Tor routing config for sing-box |
| `docs/android/orbot-custom-torrc.conf` | Multi-port Tor config for Orbot |
| `docs/android/vproxid-orbot-port-map.md` | Port-to-app allocation table |
| `docs/android/vproxid-orbot-setup.md` | Full setup documentation |
| `docs/android/verify-tor-isolation.sh` | Verifies per-port Tor circuit isolation |

## Adding a New App Later

To add an app to the per-app Tor isolation setup after initial install:

1. Pick the next available SOCKS port (check `docs/android/vproxid-orbot-port-map.md`)
2. Add `SocksPort <port> IsolateDestAddr` to Orbot's custom torrc
3. Add a SOCKS outbound + route rule in `docs/android/singbox-config.json`
4. Update the port map doc
5. Add the app to `CUSTOM_REPO_APPS` or `FDROID_MAIN_APPS` in `setup-android-apps.sh`
6. Restart Orbot and sing-box on the device
