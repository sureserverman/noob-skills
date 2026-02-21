---
name: deb-package
description: Use when creating, updating, or validating Debian .deb packages for this project ecosystem — scaffolding new packages, fixing broken control files, postinst scripts, systemd integration, or dpkg-deb build errors
---

# Debian Package Reference

## Canonical Directory Structure

```
<project>/
└── deb/
    └── package/
        ├── DEBIAN/
        │   ├── control       ← required
        │   ├── postinst      ← required if systemd/setup needed
        │   ├── preinst       ← optional, cleanup before install
        │   └── prerm         ← optional, cleanup before remove
        └── <filesystem mirror>
            ├── usr/bin/          ← binaries (755)
            ├── usr/local/bin/    ← alternative for non-system tools
            ├── etc/systemd/user/ ← user-level .service/.path/.timer
            └── etc/             ← config files
```

**Build command:** `dpkg-deb --build deb/package <name>.deb`

> Exception: ssh-menu-deb uses `package/` directly (no `deb/` wrapper) — legacy layout, don't replicate.

---

## Control File Format

```
Package: <name>
Version: <x.y.z>
Maintainer: Server Man
Architecture: all|amd64|arm64
Description: <one-line description>
Source: <repo-name>
Depends: <optional, comma-separated>
```

**Rules:**
- No trailing whitespace on `Depends:` line
- `Architecture: all` for pure-bash packages; `amd64` or `arm64` for compiled binaries
- Multi-arch compiled binaries use separate `amd64/` and `arm64/` sibling dirs

---

## postinst Patterns

### Header (always)
```bash
#!/bin/bash
```

### Root check (when needed)
```bash
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi
```

### Console user detection (systemd user units)
```bash
CONSOLE_USER="${SUDO_USER:-$USER}"
```

### Enabling systemd user units
```bash
# Enable globally for all users on future logins
systemctl --global enable <service>.path

# Activate for the installing user's current session
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
  USER_ID=$(id -u "$CONSOLE_USER" 2>/dev/null) || true
  if [ -n "$USER_ID" ] && [ -d "/run/user/$USER_ID" ]; then
    su - "$CONSOLE_USER" -c "systemctl --user daemon-reload && systemctl --user restart <service>.path" || true
  fi
fi
```

### Enabling systemd system units
```bash
systemctl daemon-reload
systemctl enable <service>
systemctl start <service>
```

### Removing stale system-level copies of user units
```bash
rm -f /etc/systemd/system/<service>.timer
rm -f /etc/systemd/system/<service>.service
systemctl daemon-reload
systemctl --global enable <service>.timer
```

---

## Validation Checklist

When auditing or before building, verify:

- [ ] Structure is `deb/package/DEBIAN/` (not `package/DEBIAN/`)
- [ ] `control` has Package, Version, Maintainer, Architecture, Description, Source
- [ ] No trailing whitespace in `control`
- [ ] `postinst` starts with `#!/bin/bash`
- [ ] `postinst` is executable (`chmod 755`)
- [ ] Binaries in `usr/bin/` have correct permissions (755)
- [ ] systemd units in `etc/systemd/user/` (not `system/`) for user-level daemons
- [ ] `postinst` uses `systemctl --global enable` (not `systemctl enable`) for user units
- [ ] Console user detection uses `"${SUDO_USER:-$USER}"` not bare `$USER`
- [ ] `dpkg-deb --build` targets `deb/package` not `package`

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `dpkg-deb --build package` | Should be `dpkg-deb --build deb/package` |
| `systemctl enable` for user unit | Use `systemctl --global enable` |
| `$USER` in postinst | Use `"${SUDO_USER:-$USER}"` |
| System unit path for user service | Put in `etc/systemd/user/` not `etc/systemd/system/` |
| Missing executable bit on postinst | `chmod 755 DEBIAN/postinst` |
| `Architecture: all` for compiled binary | Use `amd64` or `arm64` |

---

## GitHub Actions Pack Workflow Pattern

```yaml
- name: package
  run: dpkg-deb --build deb/package <name>.deb
- name: version
  run: echo "VERSION=$(grep Version deb/package/DEBIAN/control | cut -d ' ' -f 2)" >> $GITHUB_ENV
- name: sign
  run: dpkg-sig --sign builder <name>.deb
```
