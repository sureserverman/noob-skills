# sing-box + Orbot Port Allocation Map

Port assignments for per-app Tor circuit isolation.
Each SOCKS port maps to one app via sing-box route rules.

## Port Assignments

| SOCKS Port | sing-box Outbound   | App              | Package Name                              |
|------------|---------------------|------------------|-------------------------------------------|
| 9050       | —                   | (Orbot default)  | Reserved. Do not assign.                  |
| 9051       | —                   | (ControlPort)    | Tor control protocol, not SOCKS.          |
| 9052       | tor-shared          | (catch-all)      | All apps without a dedicated port.        |
| 9053       | tor-firefox         | Firefox          | org.mozilla.firefox                       |
| 9054       | tor-brave           | Brave            | com.brave.browser                         |
| 9055       | tor-jelly           | Jelly            | org.lineageos.jelly                       |
| 9056       | tor-conversations   | Conversations    | eu.siacs.conversations                    |
| 9057       | tor-threema         | Threema Libre    | ch.threema.app.libre                      |
| 9058       | tor-session         | Session          | network.loki.messenger                    |
| 9059       | tor-element         | Element X        | io.element.android.x                      |
| 9060       | tor-hypatia         | Hypatia (maintained) | org.maintainteam.hypatia                  |
| 9061       | tor-fluffychat      | FluffyChat       | chat.fluffy.fluffychat                    |
| 9062       | tor-schildichat     | SchildiChat Next | chat.schildi.android                      |
| 9063       | tor-atalk           | aTalk            | org.atalk.android                         |
| 9064       | tor-vanadium        | Vanadium         | app.vanadium.browser, app.vanadium.config |
| 9065       | tor-auditor         | Auditor          | app.attestation.auditor                   |
| 9066       | tor-simplex         | SimpleX Chat     | chat.simplex.app                          |
| 9067       | tor-tuta            | Tuta Mail        | de.tutao.tutanota                         |
| 9068       | tor-protonmail      | Proton Mail      | ch.protonmail.android                     |
| 9069       | (spare)             | —                | Available for future apps.                |

## Excluded from VPN

These apps bypass sing-box entirely (direct connection):

| Package Name                  | App               | Reason                        |
|-------------------------------|--------------------|-------------------------------|
| io.nekohasekai.sfa            | sing-box (SFA)     | VPN provider — must not loop  |
| org.torproject.android        | Orbot              | Tor daemon — needs direct net |
| app.grapheneos.update.client  | GrapheneOS Updater | System updates need direct net|

## DNS

- **Tor DNSPort**: 5400
- sing-box routes all DNS to `127.0.0.1:5400` via its `dns.servers` config
- No DNS leak — all queries go through Tor

## Config Files

- **sing-box config**: `singbox-config.json`
- **Orbot custom torrc**: `orbot-custom-torrc.conf`
- **Verification script**: `verify-tor-isolation.sh`

## Adding a New App

1. Pick the next available SOCKS port (e.g., 9069)
2. Add a `SocksPort 9069 IsolateDestAddr` line to the Orbot custom torrc
3. Add a SOCKS outbound in `singbox-config.json` with `server_port: 9069`
4. Add a route rule mapping the package to the new outbound
5. Restart Orbot and sing-box
