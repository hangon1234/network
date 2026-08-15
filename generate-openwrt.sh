#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEMPLATE="$ROOT_DIR/openwrt/files/etc/uci-defaults/99-xray.example"
OUTPUT="$ROOT_DIR/openwrt/files/etc/uci-defaults/99-xray"

usage() {
  cat <<'EOF' >&2
Usage:
  ./generate-openwrt.sh <wifi-ssid> <wifi-password> <luci-password>

Notes:
  - OpenWrt admin username is root in stock LuCI/OpenWrt.
  - This script sets the root password, Wi-Fi SSID/password, and enables xray on first boot.
EOF
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

if [ $# -ne 3 ]; then
  usage
  exit 1
fi

WIFI_SSID="$1"
WIFI_PASSWORD="$2"
LUCI_PASSWORD="$3"

sed \
  -e "s|REPLACE_WITH_WIFI_SSID|$(escape_sed_replacement "$WIFI_SSID")|g" \
  -e "s|REPLACE_WITH_WIFI_PASSWORD|$(escape_sed_replacement "$WIFI_PASSWORD")|g" \
  -e "s|REPLACE_WITH_LUCI_PASSWORD|$(escape_sed_replacement "$LUCI_PASSWORD")|g" \
  "$TEMPLATE" > "$OUTPUT"

chmod 755 "$OUTPUT"

echo "Generated: $OUTPUT"
