---
name: amo-compliance-check
description: Use when checking a Firefox extension for addons.mozilla.org (AMO) submission compliance, before packaging or publishing a Firefox WebExtension
---

# AMO Compliance Check

Systematic review of a Firefox extension against addons.mozilla.org submission requirements.

## Instructions

When invoked, identify the extension root directory (the directory containing `manifest.json` for the Firefox/Mozilla version). If unclear, ask the user.

Run every check below in order. For each section, report PASS, WARN, or FAIL with a brief explanation. At the end, provide a summary table.

## 1. Manifest — Required Fields

Read `manifest.json` and verify:

- [ ] `manifest_version` exists and is `2` or `3`
- [ ] `name` exists, is non-empty, no leading/trailing whitespace, max 50 characters
- [ ] `version` exists and matches `^(0|[1-9][0-9]{0,8})([.](0|[1-9][0-9]{0,8})){0,3}$`

## 2. Manifest — Conditional & Recommended Fields

- [ ] If `_locales/` directory exists, `default_locale` must be set. If no `_locales/`, `default_locale` must be absent
- [ ] For MV3: `browser_specific_settings.gecko.id` is present (required for AMO). For MV2: recommended
- [ ] Extension ID format is valid: email-like (`^[a-zA-Z0-9-._]*@[a-zA-Z0-9-._]+$`, max 80 chars) or GUID (`^\{[0-9a-fA-F]{8}-...}$`)
- [ ] `description` is present and max 132 characters
- [ ] `homepage_url` does NOT link to addons.mozilla.org
- [ ] `update_url` is NOT present (forbidden for AMO-hosted extensions)
- [ ] `applications` key is not used (deprecated; use `browser_specific_settings`). Invalid in MV3
- [ ] If `strict_min_version` is set, it does not use `*` wildcard
- [ ] No block comments (`/* */`) in JSON. No duplicate keys

## 3. Icons

- [ ] All icon files referenced in manifest exist on disk
- [ ] Icon files are PNG or SVG (valid extensions)
- [ ] At minimum 48px and 96px icons are provided (recommended for AMO listing)
- [ ] SVG icons (if any) include `viewBox` and `xmlns` attributes

## 4. File Structure

- [ ] No hidden files (dotfiles) in the extension directory
- [ ] No flagged binary extensions (`.exe`, `.dll`, `.so`, `.dylib`, `.bin`)
- [ ] No duplicate filenames that differ only by case
- [ ] All files referenced in `content_scripts` exist and have non-empty filenames
- [ ] All files referenced in `background.scripts` or `background.page` exist
- [ ] All files referenced in `web_accessible_resources` exist

## 5. Permissions

- [ ] Only valid WebExtension permissions are requested
- [ ] No privileged/Mozilla-internal permissions (`mozillaAddons`, etc.)
- [ ] `<all_urls>` or broad host permissions — flag as WARN (requires justification)
- [ ] Permissions appear necessary for the extension's stated functionality (flag unnecessary ones)

## 6. Security — No Remote Code

- [ ] No `<script src="http...">` or `<script src="//...">` tags in HTML files (remote script loading)
- [ ] No `fetch()`/`XMLHttpRequest` calls that load JS for execution (eval of fetched code)
- [ ] No `eval()`, `new Function()`, `setTimeout(string)`, `setInterval(string)` in JS files
- [ ] No `document.write()` usage
- [ ] If `content_security_policy` is customized, it does NOT contain `unsafe-eval`

## 7. Security — Code Quality

- [ ] No obfuscated code (check for common obfuscation patterns: long hex strings, `\x` escape sequences in bulk, base64-encoded blocks executed via eval)
- [ ] No minified code without source submission (WARN if code appears minified)
- [ ] No cryptocurrency mining patterns (`CoinHive`, `coinhive`, `crypto-loot`, miner references)

## 8. Data & Privacy

- [ ] If extension transmits any user data remotely, a privacy policy URL should be noted as required for AMO listing
- [ ] All remote requests use HTTPS, not HTTP
- [ ] No data storage patterns in private browsing context (check for `incognito` handling)

## 9. Content Scripts & Web Page Security

- [ ] Content scripts do not relax or modify page CSP
- [ ] Content scripts properly sanitize any DOM injection (no raw `innerHTML` with unsanitized external data)

## 10. Manifest V3 Specific (if applicable)

- [ ] `background.service_worker` has a `background.scripts` fallback for Firefox compatibility
- [ ] `incognito` is not set to `"split"` (unsupported in Firefox)
- [ ] `browser_specific_settings.gecko.data_collection_permissions` is present with valid values

## Summary Format

After all checks, output a table:

```
| Section                    | Status | Issues |
|----------------------------|--------|--------|
| Manifest Required Fields   | PASS   |        |
| Manifest Conditional       | WARN   | ...    |
| Icons                      | PASS   |        |
| File Structure             | PASS   |        |
| Permissions                | WARN   | ...    |
| Security — Remote Code     | PASS   |        |
| Security — Code Quality    | PASS   |        |
| Data & Privacy             | PASS   |        |
| Content Scripts            | PASS   |        |
| MV3 Specific               | N/A    |        |
```

Then list actionable items sorted by severity (FAIL first, then WARN).
