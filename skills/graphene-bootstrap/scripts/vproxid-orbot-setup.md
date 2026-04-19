# sing-box + Orbot: Per-App Tor Circuit Isolation Setup

Route each Android app through its own Tor circuit (different exit IP) using
Orbot's multi-port SOCKS and sing-box's per-app VPN routing.

## Prerequisites

- **Orbot** version 16.6.3+ (post-July 2022 — must include PR #715 fix for custom SocksPort)
- **sing-box for Android (SFA)** — io.nekohasekai.sfa
- **ADB** connected from a computer (for running the verification script)
- `curl` with SOCKS5 support on the computer (standard on most Linux/macOS)

## Architecture

```
 ┌──────────┐   VPN tunnel    ┌──────────┐   SOCKS5     ┌──────────┐
 │  App A   │ ──────────────► │          │ :9053 ─────► │          │ ── Tor Circuit 1 ── Exit A
 │  App B   │ ──────────────► │ sing-box │ :9054 ─────► │  Orbot   │ ── Tor Circuit 2 ── Exit B
 │  App C   │ ──────────────► │  (VPN)   │ :9055 ─────► │  (Tor)   │ ── Tor Circuit 3 ── Exit C
 │  others  │ ──────────────► │          │ :9052 ─────► │          │ ── Shared circuit
 └──────────┘                 └──────────┘              └──────────┘
                                  │                         │
                                  │ DNS :5400 ──────────────┘
                                  │ (Tor DNSPort)
```

sing-box occupies the Android VPN slot. Orbot runs in proxy-only mode (no VPN).
Apps with dedicated ports get isolated Tor circuits. All other apps share port 9052.
sing-box, Orbot, and the system updater are excluded from the VPN.

## Step 1: Configure Orbot

1. Open Orbot
2. Go to **Settings > General** and enable **Power User Mode**
3. Ensure VPN mode is **OFF** (Orbot should say "Proxy mode" — NOT "VPN mode")
4. Go to **Custom Torrc** (in Power User / Advanced settings)
5. Paste the contents of `orbot-custom-torrc.conf` from this directory
6. Start Orbot and wait for it to bootstrap (the onion icon turns green)

### Verify ports are open

From a computer with ADB connected:
```bash
adb forward tcp:19053 tcp:9053
curl -s --socks5-hostname 127.0.0.1:19053 https://icanhazip.com
adb forward --remove tcp:19053
```

If this fails, Orbot may be too old (pre-PR #715) or the custom torrc wasn't applied.
Restart Orbot and check the Tor log for errors.

## Step 2: Import sing-box Config

1. Push config to device: `adb push singbox-config.json /sdcard/Download/`
2. Open **SFA** app
3. Go to **Profiles** tab
4. Tap **New Profile** > **Import from File**
5. Select **Downloads > singbox-config.json**
6. Go to **Dashboard** tab, select the imported profile
7. Tap the **play button** (▶) to start the VPN
8. Accept the Android VPN permission prompt

### Critical config details

The sing-box config requires two non-obvious settings:

- **`"stack": "gvisor"`** — the `mixed` stack fails to bind TCP on Android (silent failure: DNS works but all TCP connections die)
- **Route rules must start with `sniff` + `hijack-dns`** — without these, app DNS queries are never intercepted (results in "Address not found")

## Step 3: Set as Always-On VPN

1. Go to **Android Settings > Network & internet > VPN**
2. Tap the gear icon next to SFA
3. Enable **"Always-on VPN"**
4. Optionally enable **"Block connections without VPN"** for leak prevention

## Step 4: Verify Circuit Isolation

### Quick test (manual)

Open Firefox and Brave (assigned to different ports). Visit https://check.torproject.org
in each — the displayed exit IP should differ.

### Automated test (recommended)

From the computer with ADB connected:
```bash
bash verify-tor-isolation.sh 9053 9054 9055   # test specific ports
bash verify-tor-isolation.sh                    # or auto-detect all Orbot SOCKS ports
```

### SOCKS connection health check

```bash
adb shell ss -tn | grep '127.0.0.1:905'
```

All connections should show `Recv-Q 0` (no unread data).

### Control port deep verification

If `ControlPort 9051` is in the torrc:
```bash
adb forward tcp:19051 tcp:9051
echo -e 'AUTHENTICATE\r\nGETCONF SocksPort\r\nQUIT\r' | nc 127.0.0.1 19051
adb forward --remove tcp:19051
```

## Boot Start & Battery Optimization

Orbot must start at boot before sing-box tries to route traffic through its SOCKS ports.

### Battery optimization (critical — both apps)

Exempt both from battery optimization:
```bash
adb shell dumpsys deviceidle whitelist +org.torproject.android
adb shell dumpsys deviceidle whitelist +io.nekohasekai.sfa
```

Or via Settings: Apps > Orbot/SFA > Battery > **Unrestricted**.

### Boot timing

After a reboot, expect ~10-30 seconds of no connectivity while Orbot bootstraps:

1. Device powers on
2. User unlocks (credential-encrypted storage available)
3. Always-on VPN (sing-box) starts immediately
4. `BOOT_COMPLETED` delivered → Orbot starts Tor daemon
5. Orbot bootstraps (10-30 sec) → SOCKS ports become available
6. sing-box connects to SOCKS ports → apps gain Tor connectivity

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Address not found" in browser | DNS not intercepted | Ensure `sniff` + `hijack-dns` rules are first in route rules |
| DNS works but pages don't load | TCP stack broken | Use `"stack": "gvisor"` not `"mixed"` |
| curl to port 9053 hangs | Orbot not running or torrc not applied | Restart Orbot, check torrc |
| All ports return same IP | Ports not isolated | Update Orbot; check sing-box route rules |
| "VPN already in use" error | Orbot is in VPN mode | Disable VPN in Orbot, use proxy-only mode |
| Apps have no internet after boot | sing-box started before Orbot bootstrapped | Wait 10-30 sec after unlock |
| Connection drops after screen off | Android killed Orbot/SFA | Disable battery optimization for both |

## Limitations

- **Orbot UI blind spot**: Orbot only shows the primary port (9050) status. Custom ports work at the Tor level but aren't visible in Orbot's UI.
- **Boot gap**: ~10-30 seconds of no connectivity after reboot while Tor bootstraps.
- **Circuit rotation**: Tor rotates circuits every ~10 minutes by default. Exit IPs change over time (this is expected behavior, not a bug).

## Files in This Directory

- `singbox-config.json` — sing-box config with per-app SOCKS routing
- `orbot-custom-torrc.conf` — Multi-port torrc configuration for Orbot
- `vproxid-orbot-port-map.md` — Port-to-app allocation table
- `verify-tor-isolation.sh` — ADB-based script to verify circuit isolation
