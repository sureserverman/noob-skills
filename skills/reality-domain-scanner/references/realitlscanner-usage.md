# RealiTLScanner Usage

Tool: [XTLS/RealiTLScanner](https://github.com/XTLS/RealiTLScanner) — TLS server scanner for finding VLESS Reality–suitable SNI targets.

## Build

```bash
git clone https://github.com/XTLS/RealiTLScanner.git
cd RealiTLScanner
go build -o RealiTLScanner .
```

## CLI

```
./RealiTLScanner [input] [options] [output]
```

### Input (one of)

| Flag | Meaning | Example |
|------|---------|--------|
| `-addr` | IP, CIDR, or domain | `-addr 1.2.3.4` or `-addr 10.0.0.0/24` |
| `-in` | File with targets (one per line) | `-in targets.txt` |
| `-url` | Crawl domains from URL | `-url https://example.com` |

### Options

| Flag | Default | Meaning |
|------|---------|--------|
| `-port` | 443 | TCP port to scan |
| `-thread` | 1 | Concurrency |
| `-timeout` | 10 | Per-scan timeout (seconds) |
| `-v` | — | Verbose (include failed scans) |

### Output

| Flag | Default | Meaning |
|------|---------|--------|
| `-out` | `out.csv` | Output CSV path |

## CSV Format

Header and columns:

```csv
IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
202.70.64.2,ntc.net.np,*.ntc.net.np,"GlobalSign nv-sa",NP
```

- **IP**: Scanned address.
- **ORIGIN**: Origin/hostname if applicable.
- **CERT_DOMAIN**: Domain from the TLS certificate (use this for Reality SNI). May be wildcard (`*.example.com`).
- **CERT_ISSUER**: Certificate issuer.
- **GEO_CODE**: Country code (if MaxMind `Country.mmdb` is in the same directory).

Only rows that pass the scanner’s feasibility check (TLS 1.3, HTTP/2 ALPN, valid cert) are written. So every row is a candidate for Reality; the skill then filters by “working” (HTTP reachable) and category (gaming/entertainment/news/shop).

## Notes

- Run locally when possible; scanning from a cloud VPS can get the IP flagged.
- For one IP: `-addr <IP> -out reality_scan.csv -thread 4 -timeout 10`.
