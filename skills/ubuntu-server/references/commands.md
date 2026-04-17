# Ubuntu Command Reference

Generic Ubuntu administration commands. Consult when you need a specific command; default to the inline guidance in `SKILL.md` for the workflow (troubleshooting order, SSH version differences, Ansible preflight).

## Package Management (apt)

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

## Users and Permissions

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

## Networking

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

## Firewall (UFW)

```bash
ufw status verbose
ufw app list
ufw allow <port>/tcp
ufw allow OpenSSH

# Check underlying rules
iptables -L -n -v
nft list ruleset  # 24.04 uses nftables backend by default
```

## Quick Reference

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
journalctl -b       # current boot
journalctl -b -1    # previous boot
```
