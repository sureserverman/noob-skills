# Domain Classification for Reality Scanner

Domains from RealiTLScanner are classified by fetching `https://<domain>/` and matching (case-insensitive) against keywords in the response body (e.g. first 50KB), including `<title>` and `<meta name="description" content="...">`.

## Categories and Keywords

### Gaming

- game, games, gaming, gameplay, play, player
- steam, epic games, gog, origin
- xbox, playstation, nintendo, pc gaming
- twitch (in gaming context), esport, esports
- mmorpg, fps, rpg, multiplayer

### Entertainment

- streaming, stream, watch, movie, film, films, tv, television
- music, podcast, podcasts, listen
- netflix, spotify, youtube, disney+, hulu, prime video
- entertainment, series, show, shows
- radio, audiobook

### News

- news, breaking, headline, headlines
- reuters, associated press, ap news, bbc news, cnn, al jazeera
- editorial, journalism, reporter, reporting
- daily, times, post (when with news context), gazette

### Shop / Marketplace

- shop, store, stores, shopping, retail
- buy, purchase, cart, checkout, order
- amazon, ebay, marketplace, etsy
- sale, deals, discount, price, prices
- product, products, catalog

## Matching Rules

1. **First match wins**: Check in order gaming → entertainment → news → shop. Assign the first category whose keyword set matches.
2. **Substring**: Keyword need only appear as a substring (e.g. "streaming" in "live streaming").
3. **Avoid false positives**: Prefer matching in `<title>` or `<meta name="description">` when possible; if the whole body is used, one clear keyword match is enough.
4. **No match**: If no category matches, do **not** count the domain toward the three; skip and try the next candidate.
5. **One category per domain**: Assign at most one category (the first that matches).

## Fetch Limits

- Use `curl -sL --max-time 8` and optionally `--max-filesize 51200` (50KB) to avoid long or huge responses.
- If the fetch fails (timeout, connection error, non-2xx), treat the domain as not “working” and skip classification.
