# Ubuntu Server Skill (22.04 LTS / 24.04 LTS)

Use this skill when working with Ubuntu servers. Always identify the Ubuntu version first and apply version-specific knowledge.

## Version Identification

**IMPORTANT: This skill is for remote server administration. Do NOT run commands locally to check versions.**

Always ASK the user for:
- The Ubuntu version on the remote server (22.04 or 24.04)
- How they connect to it (SSH, console, etc.)
- What issue they're experiencing

If the user doesn't know the server version, suggest they run these commands on the **remote server**:
```bash
lsb_release -a
cat /etc/os-release
uname -r
```

## Key Differences: 22.04 vs 24.04

### Package Versions
| Component | 22.04 (Jammy) | 24.04 (Noble) |
|-----------|---------------|---------------|
| Kernel | 5.15 | 6.8 |
| OpenSSH | 8.9 | 9.6 |
| Python | 3.10 | 3.12 |
| systemd | 249 | 255 |
| netplan | 0.104 | 0.109 |

### Notable Changes in 24.04
- **SSH**: `ssh.socket` (socket activation) enabled by default instead of `ssh.service`
- **Networking**: netplan changes, NetworkManager more prominent
- **AppArmor**: Stricter default profiles
- **UFW**: Updated nftables backend
- **Snap**: More system components delivered as snaps

Check changelogs for specific packages:
```bash
apt changelog <package-name>
```

## System Administration

### Services (systemd)
```bash
# Status and control
systemctl status <service>
systemctl start/stop/restart <service>
systemctl enable/disable <service>

# List services
systemctl list-units --type=service
systemctl list-unit-files --type=service

# Check for socket activation (important for SSH in 24.04)
systemctl list-units --type=socket
systemctl status ssh.socket  # 24.04 default

# Logs for a service
journalctl -u <service> -e
journalctl -u <service> --since "1 hour ago"
```

### Package Management (apt)
```bash
# Update and upgrade
apt update && apt upgrade

# Search and info
apt search <name>
apt show <package>
apt policy <package>  # shows version and sources

# List installed
dpkg -l | grep <pattern>
apt list --installed | grep <pattern>

# Check what changed in a package
apt changelog <package>
```

### Users and Permissions
```bash
# User management
id <user>
groups <user>
usermod -aG <group> <user>

# File permissions
ls -la <path>
stat <file>
getfacl <file>  # ACLs

# SSH key permissions (critical)
# ~/.ssh directory: 700
# ~/.ssh/authorized_keys: 600
# private keys: 600
# public keys: 644
```

### Networking
```bash
# IP configuration
ip addr
ip route
ss -tlnp  # listening ports

# Netplan (Ubuntu's network config)
cat /etc/netplan/*.yaml
netplan try  # test changes
netplan apply

# DNS
resolvectl status
cat /etc/resolv.conf
```

### Firewall (UFW)
```bash
ufw status verbose
ufw app list
ufw allow <port>/tcp
ufw allow OpenSSH

# Check underlying rules
iptables -L -n -v
nft list ruleset  # 24.04 nftables
```

## Troubleshooting Protocol

**ALWAYS follow this order - gather evidence before hypothesizing:**

### 1. Identify the Symptom
- What exactly is failing?
- What error message appears?
- When did it start?

### 2. Check Logs First
```bash
# System logs
journalctl -xe
journalctl --since "10 minutes ago"
dmesg | tail -50

# Service-specific
journalctl -u <service> -e

# Auth/security
cat /var/log/auth.log | tail -100
cat /var/log/syslog | tail -100
```

### 3. Compare Working vs Non-Working
If it works on one system but not another:
```bash
# Package versions
dpkg -l | grep <relevant-package>

# Config differences
diff /etc/<config> /path/to/working/<config>

# Service status
systemctl status <service>
```

### 4. Check Version-Specific Changes
```bash
apt changelog <package> | head -100
```
Search for changes between the specific versions.

### 5. Only Then Hypothesize
Form hypotheses based on evidence, not guesses.

## SSH Specific

SSH is critical infrastructure. Always diagnose systematically:

```bash
# Client-side verbose output
ssh -vvv user@host

# Server-side status (version matters!)
# Ubuntu 22.04:
systemctl status ssh

# Ubuntu 24.04 (socket activation default):
systemctl status ssh.socket
systemctl status ssh.service

# Server logs
journalctl -u ssh -e
cat /var/log/auth.log | tail -50

# Config check
sshd -T | grep -E 'pubkey|password|permit|authorized'

# Permissions check
ls -la ~/.ssh/
ls -la /etc/ssh/
ls -la /etc/ssh/sshd_config.d/

# Test config validity
sshd -t
```

### Common SSH Issues by Version

**24.04 specific:**
- Socket activation: `ssh.socket` must be enabled, not just `ssh.service`
- Check `/etc/ssh/sshd_config.d/` for drop-in configs that override main config
- Stricter default crypto policies

**Both versions:**
- Permission denied: Check `~/.ssh` (700) and `authorized_keys` (600)
- PAM issues: Check `/etc/pam.d/sshd`
- SELinux/AppArmor: Check `aa-status`, audit logs

## Infrastructure / Ansible

When running Ansible or provisioning workflows:

### Pre-flight Checks
```bash
# Target system reachable
ping <host>
ssh -o BatchMode=yes <host> echo "OK"

# Python available (Ansible requirement)
ssh <host> "python3 --version"
```

### After Running Workflows
```bash
# Verify services
systemctl status <expected-services>

# Check for failed units
systemctl --failed

# Review recent changes
journalctl --since "5 minutes ago"
```

### Debugging Ansible Issues
```bash
# Run with verbose output
ansible-playbook -vvv playbook.yml

# Check mode (dry run)
ansible-playbook --check --diff playbook.yml

# Limit to specific host
ansible-playbook -l <host> playbook.yml
```

## Quick Reference Commands

```bash
# System info
hostnamectl
timedatectl
free -h
df -h
lscpu

# Process investigation
ps aux | grep <name>
top -c
htop

# Recent logins
last
lastlog
who

# Boot issues
systemd-analyze
systemd-analyze blame
journalctl -b  # current boot
journalctl -b -1  # previous boot
```
