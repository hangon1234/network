#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEMPLATE="$ROOT_DIR/openwrt/templates/99-xray.example"
OUTPUT="$ROOT_DIR/openwrt/files/etc/uci-defaults/99-xray"
SHADOW_OUTPUT="$ROOT_DIR/openwrt/files/etc/shadow"

usage() {
  cat <<'EOF' >&2
Usage:
  ./generate-openwrt.sh <wifi-ssid> <wifi-password> <luci-password>

Notes:
  - OpenWrt admin username is root in stock LuCI/OpenWrt.
  - This script sets the root password, Wi-Fi SSID/password, xray routing, and enables xray on first boot.
EOF
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

generate_password_hash() {
  local password="$1"

  if command -v openssl >/dev/null 2>&1; then
    openssl passwd -6 "$password" 2>/dev/null || openssl passwd -1 "$password"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import crypt; print(crypt.crypt('$password', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null && return
  fi

  echo "error: openssl or python3 is required to generate password hash" >&2
  exit 1
}

if [ $# -ne 3 ]; then
  usage
  exit 1
fi

WIFI_SSID="$1"
WIFI_PASSWORD="$2"
LUCI_PASSWORD="$3"

PASSWORD_HASH="$(generate_password_hash "$LUCI_PASSWORD")"

sed \
  -e "s|REPLACE_WITH_WIFI_SSID|$(escape_sed_replacement "$WIFI_SSID")|g" \
  -e "s|REPLACE_WITH_WIFI_PASSWORD|$(escape_sed_replacement "$WIFI_PASSWORD")|g" \
  -e "s|REPLACE_WITH_ROOT_PASSWORD_HASH|$(escape_sed_replacement "$PASSWORD_HASH")|g" \
  "$TEMPLATE" > "$OUTPUT"

chmod 755 "$OUTPUT"

mkdir -p "$(dirname "$SHADOW_OUTPUT")"
cat <<EOF > "$SHADOW_OUTPUT"
root:${PASSWORD_HASH}:0:0:99999:7:::
daemon:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
ntp:x:0:0:99999:7:::
dnsmasq:x:0:0:99999:7:::
logd:x:0:0:99999:7:::
ubus:x:0:0:99999:7:::
EOF
chmod 600 "$SHADOW_OUTPUT"

echo "Generated: $OUTPUT"
echo "Generated: $SHADOW_OUTPUT"
