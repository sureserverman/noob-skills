#!/usr/bin/env bash
# verify-tor-isolation.sh — Confirm per-port Tor circuit isolation
#
# Runs from the computer connected to the Android device via ADB.
# Uses adb forward to tunnel device SOCKS ports to local ports, then
# tests each with curl (which has SOCKS5 support, unlike Android's curl).
#
# Requirements:
#   - adb connected to device (adb devices shows it)
#   - curl with SOCKS5 support on this machine
#   - Orbot running on the device with custom torrc SocksPort lines
#
# Usage:
#   bash verify-tor-isolation.sh                    # auto-detect listening ports
#   bash verify-tor-isolation.sh 9050 9052 9055     # test specific device ports

set -euo pipefail

LOCAL_OFFSET=10000  # local port = device port + offset (avoids conflicts with local Tor)
HOST="127.0.0.1"
IP_CHECK_URLS=(
    "https://icanhazip.com"
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
)
TIMEOUT=30

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Detect or accept device ports ---

if [[ $# -gt 0 ]]; then
    DEVICE_PORTS=("$@")
else
    echo -e "${CYAN}Auto-detecting Orbot SOCKS ports on device...${NC}"
    # Find Orbot's UID from its running process
    ORBOT_UID=$(adb shell "ps -A -o UID,NAME" 2>/dev/null \
        | grep 'org.torproject.android' | awk '{print $1}' | head -1) || true

    if [[ -z "$ORBOT_UID" ]]; then
        echo -e "${RED}Orbot does not appear to be running on the device.${NC}"
        exit 1
    fi

    # Parse /proc/net/tcp for LISTEN sockets owned by Orbot
    # Format: local_address(hex) ... state(0A=LISTEN) ... uid
    mapfile -t DEVICE_PORTS < <(
        adb shell "cat /proc/net/tcp" 2>/dev/null \
        | awk -v uid="$ORBOT_UID" '
            $4 == "0A" && $8 == uid {
                split($2, a, ":")
                port = strtonum("0x" a[2])
                if (port >= 9050 && port <= 9999) print port
            }
        ' | sort -n
    )

    if [[ ${#DEVICE_PORTS[@]} -eq 0 ]]; then
        echo -e "${RED}No SOCKS ports (9050-9999) found for Orbot (uid $ORBOT_UID).${NC}"
        echo "Check that Orbot is running and custom torrc ports are configured."
        exit 1
    fi

    echo "Found ${#DEVICE_PORTS[@]} ports: ${DEVICE_PORTS[*]}"
fi

echo ""
echo -e "${CYAN}=== Tor Per-Port Circuit Isolation Verification ===${NC}"
echo "Timestamp: $(date -Iseconds)"
echo "IP check endpoints: ${IP_CHECK_URLS[*]}"
echo "Testing ${#DEVICE_PORTS[@]} device ports via ADB forward"
echo ""

# --- Set up ADB port forwards ---

cleanup() {
    echo ""
    echo "Cleaning up ADB forwards..."
    for dp in "${DEVICE_PORTS[@]}"; do
        adb forward --remove "tcp:$(( dp + LOCAL_OFFSET ))" 2>/dev/null || true
    done
}
trap cleanup EXIT

for dp in "${DEVICE_PORTS[@]}"; do
    local_port=$(( dp + LOCAL_OFFSET ))
    adb forward "tcp:${local_port}" "tcp:${dp}" >/dev/null 2>&1 || {
        echo -e "${RED}Failed to forward local:${local_port} -> device:${dp}${NC}"
        exit 1
    }
done

# Brief pause for forwards to settle
sleep 1

# --- Test each port ---

declare -A PORT_IP
FAILURES=0

for dp in "${DEVICE_PORTS[@]}"; do
    local_port=$(( dp + LOCAL_OFFSET ))
    printf "Device port %-5s → " "$dp"

    # Try each IP check endpoint until one succeeds (some exits block specific services)
    EXIT_IP=""
    for url in "${IP_CHECK_URLS[@]}"; do
        EXIT_IP=$(curl -s --max-time "$TIMEOUT" \
            --socks5-hostname "${HOST}:${local_port}" \
            "$url" 2>/dev/null | tr -d '[:space:]') || true
        [[ -n "$EXIT_IP" ]] && break
    done

    if [[ -z "$EXIT_IP" ]]; then
        echo -e "${RED}FAILED${NC} (all endpoints failed — circuit may be down)"
        ((FAILURES++)) || true
        continue
    fi

    PORT_IP[$dp]="$EXIT_IP"

    # Check for duplicate exit IPs
    DUPLICATE=false
    for prev_port in "${!PORT_IP[@]}"; do
        if [[ "$prev_port" != "$dp" && "${PORT_IP[$prev_port]}" == "$EXIT_IP" ]]; then
            DUPLICATE=true
            echo -e "${YELLOW}${EXIT_IP}${NC}  (same exit as port ${prev_port})"
            break
        fi
    done

    if [[ "$DUPLICATE" == false ]]; then
        echo -e "${GREEN}${EXIT_IP}${NC}"
    fi
done

# --- Summary ---

echo ""
echo -e "${CYAN}=== Summary ===${NC}"

SUCCESSFUL=$(( ${#DEVICE_PORTS[@]} - FAILURES ))
echo "Ports tested:  ${#DEVICE_PORTS[@]}"
echo "Successful:    $SUCCESSFUL"
echo "Failed:        $FAILURES"

if [[ ${#PORT_IP[@]} -gt 0 ]]; then
    mapfile -t SORTED_IPS < <(printf '%s\n' "${PORT_IP[@]}" | sort -u)
    echo "Distinct IPs:  ${#SORTED_IPS[@]}"

    if [[ ${#SORTED_IPS[@]} -eq $SUCCESSFUL && $FAILURES -eq 0 ]]; then
        echo -e "\n${GREEN}PASS: All ports have different exit IPs. Circuit isolation is working.${NC}"
    elif [[ ${#SORTED_IPS[@]} -eq $SUCCESSFUL ]]; then
        echo -e "\n${YELLOW}PASS (with failures): Working ports have unique IPs, but $FAILURES port(s) failed.${NC}"
    elif [[ ${#SORTED_IPS[@]} -gt 1 ]]; then
        echo -e "\n${YELLOW}PARTIAL: Some ports share exit IPs. Re-run to confirm — Tor may reuse exits transiently.${NC}"
    else
        echo -e "\n${RED}FAIL: All ports share the same exit IP. Circuit isolation is NOT working.${NC}"
    fi
else
    echo -e "\n${RED}FAIL: No ports responded.${NC}"
fi
