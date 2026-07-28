#!/usr/bin/env bash

set -Eeuo pipefail

echo "========== Cloudflare WARP =========="

# Create TUN device if missing
if [ ! -c /dev/net/tun ]; then
    echo "[INIT] Creating /dev/net/tun..."
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200 || true
    sudo chmod 600 /dev/net/tun
fi

# Start DBus
echo "[INIT] Starting DBus..."
sudo mkdir -p /run/dbus
sudo rm -f /run/dbus/pid

if ! pgrep dbus-daemon >/dev/null 2>&1; then
    sudo dbus-daemon --system
fi

# Start Cloudflare WARP service
echo "[INIT] Starting warp-svc..."
sudo warp-svc --accept-tos &

sleep "${WARP_SLEEP:-2}"

# Register if necessary
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    echo "[WARP] Registering..."

    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "${REGISTER_WHEN_MDM_EXISTS:-}" ]; then

        warp-cli registration new

        if [ -n "${WARP_LICENSE_KEY:-}" ]; then
            echo "[WARP] Activating WARP+..."
            warp-cli registration license "$WARP_LICENSE_KEY"
        fi
    fi
else
    echo "[WARP] Already registered."
fi

# Enable / Disable qlog
if [ -n "${DEBUG_ENABLE_QLOG:-}" ]; then
    warp-cli --accept-tos debug qlog enable
else
    warp-cli --accept-tos debug qlog disable
fi

# Select mode
if [ -n "${WARP_ENABLE_NAT:-}" ]; then
    echo "[WARP] Switching to WARP mode..."
    warp-cli --accept-tos mode warp
else
    echo "[WARP] Switching to Proxy mode..."
    warp-cli --accept-tos mode proxy
fi

echo "[WARP] Connecting..."
warp-cli --accept-tos connect

sleep "${WARP_SLEEP:-2}"

# Enable NAT
if [ -n "${WARP_ENABLE_NAT:-}" ]; then

    echo "[NAT] Configuring nftables..."

    sudo nft list table ip nat >/dev/null 2>&1 || sudo nft add table ip nat

    sudo nft list chain ip nat WARP_NAT >/dev/null 2>&1 || \
        sudo nft add chain ip nat WARP_NAT "{ type nat hook postrouting priority 100; }"

    sudo nft add rule ip nat WARP_NAT oifname "CloudflareWARP" masquerade 2>/dev/null || true

    sudo nft list table ip6 nat >/dev/null 2>&1 || sudo nft add table ip6 nat

    sudo nft list chain ip6 nat WARP_NAT >/dev/null 2>&1 || \
        sudo nft add chain ip6 nat WARP_NAT "{ type nat hook postrouting priority 100; }"

    sudo nft add rule ip6 nat WARP_NAT oifname "CloudflareWARP" masquerade 2>/dev/null || true
fi

echo "[Gost] Starting..."
exec gost ${GOST_ARGS:--L :1080}
