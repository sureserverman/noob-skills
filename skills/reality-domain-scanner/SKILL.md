---
name: reality-domain-scanner
description: Use when the user asks to find Reality domains for an IP, scan for VLESS/Reality SNI targets, get gaming/entertainment/news/shop domains for Reality, or mentions RealiTLScanner. Trigger on "find reality domains", "scan this IP for reality", "get vless SNI targets", "set up Reality SNI", "configure VLESS on this VPS", or when the user pastes a raw IP address alongside Reality/XTLS/VLESS context.
---

# Reality Domain Scanner (RealiTLScanner + Classification)

Find domains suitable for **VLESS Reality** from a given IP: run RealiTLScanner, verify each domain works, classify as **gaming**, **entertainment**, **news**, or **shop/marketplace**, then stop after **three** such domains and display them.

## Prerequisites

- **RealiTLScanner** installed and on `PATH`. Build from source:
  ```bash
  git clone https://github.com/XTLS/RealiTLScanner.git && cd RealiTLScanner && go build -o RealiTLScanner .
  ```
- `curl` available for reachability and classification fetches.
- User provides a single **IP address** (or CIDR/domain; skill focuses on single IP).

## Default workflow: use the bundled script

From the skill directory (or with `SKILL_DIR` set), run:

```bash
./scripts/scan-and-classify.sh <IP> [output_csv]
```

- Uses **RealiTLScanner** from `PATH` or `REALITLSCANNER` env.
- Writes scanner CSV to `output_csv` (default: `reality_scan.csv`), then parses it, verifies each domain, classifies (gaming/entertainment/news/shop), and prints a markdown table of up to three working classified domains.
- When invoking from another directory: `"$SKILL_DIR/scripts/scan-and-classify.sh" <IP>` or `bash /path/to/skills/reality-domain-scanner/scripts/scan-and-classify.sh <IP>`.

This is the primary path. Report the script's output to the user. Only fall through to the manual steps below if the script is unavailable, errors out, or the user explicitly asks for a step-by-step walk-through.

<details>
<summary>Manual steps (fallback — only if the script is unavailable)</summary>

### 1. Run RealiTLScanner

With the user-provided IP (e.g. `1.2.3.4`):

```bash
./RealiTLScanner -addr <IP> -port 443 -out reality_scan.csv -thread 4 -timeout 10
```

If the binary is elsewhere, use its full path. Default output file is `out.csv` when `-out` is omitted.

### 2. Parse Domains from CSV

- CSV columns: `IP`, `ORIGIN`, `CERT_DOMAIN`, `CERT_ISSUER`, `GEO_CODE`.
- Extract unique **CERT_DOMAIN** values (skip empty). For wildcards like `*.example.com`, use the apex `example.com` for checks.
- Process domains in order until three classified matches are found.

### 3. Verify Domain Is Working

For each candidate domain:

```bash
curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://<domain>/"
```

- **200, 301, 302**: consider working.
- **4xx/5xx or 000**: skip this domain and continue with the next.

### 4. Classify Domain

Fetch the homepage and match against category keywords (case-insensitive) in page content (e.g. first 50KB of HTML, including `<title>` and `<meta name="description">`).

**Categories and keywords** (see [references/classification.md](references/classification.md) for full list):

| Category | Example keywords |
|----------|------------------|
| **Gaming** | game, gaming, play, steam, epic, xbox, playstation, nintendo, twitch (gaming), esport |
| **Entertainment** | streaming, movie, film, tv, music, netflix, spotify, youtube, podcast, entertainment |
| **News** | news, breaking, reuters, ap news, bbc, cnn, headline, editorial |
| **Shop / Marketplace** | shop, store, buy, cart, checkout, amazon, ebay, marketplace, shopping, retail |

If **any** keyword for a category appears in the fetched content, tag the domain with that category. If multiple categories match, pick one (e.g. first match in order: gaming → entertainment → news → shop). Domains that match **none** are skipped; do not count them toward the three.

### 5. Stop at Three and Report

- After finding **three** domains that are both **working** and **classified** (gaming, entertainment, news, or shop), stop scanning.
- If the scanner CSV is exhausted before three, report how many were found (one or two) and list them.

**Output format:**

```markdown
## Reality-capable domains (working + classified)

| # | Domain | Category | Status |
|---|--------|----------|--------|
| 1 | example.com | entertainment | working |
| 2 | news.example.org | news | working |
| 3 | shop.example.net | shop | working |
```

Add a short note that these domains are suitable for use as SNI/targets for VLESS Reality from the scanned IP.

</details>

## Rules

- **Single IP focus**: When the user gives one IP, use `-addr <IP>`. If they give a list or file, use `-in` as per RealiTLScanner docs.
- **No cloud scanning**: Prefer running RealiTLScanner locally; cloud/VPS scanning can get the IP flagged.
- **Respect rate**: Use a reasonable `-thread` (e.g. 4) and `-timeout` (e.g. 10) to avoid hammering targets.
- **Wildcards**: For `CERT_DOMAIN` like `*.cdn.example.com`, use `cdn.example.com` or `example.com` for the HTTPS check and classification fetch.

## Optional: Custom Output Path

If the user wants results in a specific path:

```bash
./RealiTLScanner -addr <IP> -out /path/to/results.csv
```

Parse from that file in step 2.

## Example

User says: "Find Reality domains for IP 1.2.3.4." → from the skill dir, run `./scripts/scan-and-classify.sh 1.2.3.4` and report the script output.

## Reference

- RealiTLScanner usage and CSV format: [references/realitlscanner-usage.md](references/realitlscanner-usage.md)
- Classification keywords and edge cases: [references/classification.md](references/classification.md)
