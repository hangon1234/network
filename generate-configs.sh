#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_TEMPLATE="$ROOT_DIR/server.example.json"
CLIENT_TEMPLATE="$ROOT_DIR/client.example.json"
ROUTER_TEMPLATE="$ROOT_DIR/openwrt/templates/config.example.json"
OPENWRT_TEMPLATE="$ROOT_DIR/openwrt/templates/99-xray.example"

SERVER_OUTPUT="$ROOT_DIR/server.json"
CLIENT_OUTPUT="$ROOT_DIR/client.json"
ROUTER_OUTPUT="$ROOT_DIR/openwrt/files/etc/xray/config.json"
OPENWRT_OUTPUT="$ROOT_DIR/openwrt/files/etc/uci-defaults/99-xray"
SHADOW_OUTPUT="$ROOT_DIR/openwrt/files/etc/shadow"
ONEXRAY_SHARE_OUTPUT="$ROOT_DIR/onexray-share.txt"
ONEXRAY_QR_OUTPUT="$ROOT_DIR/onexray-share.png"
ROUTER_LABEL_OUTPUT="$ROOT_DIR/router-label.html"

usage() {
  cat <<'EOF' >&2
Usage:
  ./generate-configs.sh <server-address-or-domain> <wifi-ssid> <wifi-password> <luci-password> [server-name]

Arguments:
  server-address-or-domain  Xray server address used by client/router configs.
  wifi-ssid                 Wi-Fi SSID to set on the OpenWrt router.
  wifi-password             Wi-Fi password to set on the OpenWrt router.
  luci-password             LuCI/SSH root password for the OpenWrt router.
  server-name               REALITY SNI / camouflage name. Defaults to speed.cloudflare.com.

This generates:
  - server.json
  - client.json
  - openwrt/files/etc/xray/config.json
  - openwrt/files/etc/uci-defaults/99-xray
  - openwrt/files/etc/shadow
  - onexray-share.txt
  - onexray-share.png
EOF
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi

  if [ -r /proc/sys/kernel/random/uuid ]; then
    tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid
    return
  fi

  echo "error: unable to generate UUID; install uuidgen or expose /proc/sys/kernel/random/uuid" >&2
  exit 1
}

generate_short_id() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 8
    return
  fi

  if [ -r /dev/urandom ]; then
    od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
    printf '\n'
    return
  fi

  echo "error: unable to generate shortId; install openssl or expose /dev/urandom" >&2
  exit 1
}

generate_reality_keys() {
  if ! command -v xray >/dev/null 2>&1; then
    echo "error: xray is required to generate REALITY key pairs" >&2
    exit 1
  fi

  local output private_key public_key
  output="$(xray x25519 2>&1)"
  private_key="$(printf '%s\n' "$output" | awk -F': ' '
    /^Private key:/ {print $2; exit}
    /^PrivateKey:/ {print $2; exit}
  ')"
  public_key="$(printf '%s\n' "$output" | awk -F': ' '
    /^Public key:/ {print $2; exit}
    /^Password \(PublicKey\):/ {print $2; exit}
  ')"

  if [ -z "$private_key" ] || [ -z "$public_key" ]; then
    echo "error: failed to parse xray x25519 output" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  printf '%s\n%s\n' "$private_key" "$public_key"
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

generate_onexray_share() {
  local server_address="$1"
  local server_name="$2"
  local uuid="$3"
  local public_key="$4"
  local short_id="$5"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required to generate the OneXray QR code" >&2
    exit 1
  fi

  if ! python3 - <<'PY' >/dev/null 2>&1
from reportlab.graphics.barcode import qr
from reportlab.graphics import renderPM
PY
  then
    echo "error: python3 reportlab is required to generate the OneXray QR code" >&2
    exit 1
  fi

  local share_url
  share_url="$(
    python3 - "$server_address" "$server_name" "$uuid" "$public_key" "$short_id" <<'PY'
import sys
from urllib.parse import quote

server_address, server_name, uuid, public_key, short_id = sys.argv[1:]

if server_address.startswith('[') and server_address.endswith(']'):
    host = server_address
elif ':' in server_address:
    host = f'[{server_address}]'
else:
    host = server_address

params = [
    ("type", "xhttp"),
    ("security", "reality"),
    ("encryption", "none"),
    ("pbk", public_key),
    ("sid", short_id),
    ("sni", server_name),
    ("fp", "chrome"),
    ("path", "/xray"),
    ("mode", "stream-one"),
]

query = "&".join(f"{key}={quote(value, safe='')}" for key, value in params)
print(f"vless://{uuid}@{host}:443?{query}")
PY
  )"

  printf '%s\n' "$share_url" > "$ONEXRAY_SHARE_OUTPUT"

  python3 - "$share_url" "$ONEXRAY_QR_OUTPUT" <<'PY'
import sys
from reportlab.graphics.barcode import qr
from reportlab.graphics import renderPM
from reportlab.graphics.shapes import Drawing

data, output = sys.argv[1:]
widget = qr.QrCodeWidget(data)
bounds = widget.getBounds()
width = bounds[2] - bounds[0]
height = bounds[3] - bounds[1]
size = max(width, height)
drawing = Drawing(size, size, transform=[size / width, 0, 0, size / height, 0, 0])
drawing.add(widget)
renderPM.drawToFile(drawing, output, fmt='PNG')
PY
}

render_template() {
  local template="$1"
  local output="$2"
  local server_address="$3"
  local server_name="$4"
  local uuid="$5"
  local private_key="$6"
  local public_key="$7"
  local short_id="$8"

  sed \
    -e "s|YOUR_SERVER_DOMAIN_OR_IP|$(escape_sed_replacement "$server_address")|g" \
    -e "s|speed.cloudflare.com|$(escape_sed_replacement "$server_name")|g" \
    -e "s|REPLACE_WITH_UUID|$(escape_sed_replacement "$uuid")|g" \
    -e "s|REPLACE_WITH_PRIVATE_KEY|$(escape_sed_replacement "$private_key")|g" \
    -e "s|REPLACE_WITH_PUBLIC_KEY|$(escape_sed_replacement "$public_key")|g" \
    -e "s|0123456789abcdef|$(escape_sed_replacement "$short_id")|g" \
    "$template" > "$output"
}

generate_openwrt_defaults() {
  local wifi_ssid="$1"
  local wifi_password="$2"
  local password_hash="$3"

  sed \
    -e "s|REPLACE_WITH_WIFI_SSID|$(escape_sed_replacement "$wifi_ssid")|g" \
    -e "s|REPLACE_WITH_WIFI_PASSWORD|$(escape_sed_replacement "$wifi_password")|g" \
    -e "s|REPLACE_WITH_ROOT_PASSWORD_HASH|$(escape_sed_replacement "$password_hash")|g" \
    "$OPENWRT_TEMPLATE" > "$OPENWRT_OUTPUT"

  chmod 755 "$OPENWRT_OUTPUT"

  mkdir -p "$(dirname "$SHADOW_OUTPUT")"
  cat > "$SHADOW_OUTPUT" <<EOF
root:${password_hash}:0:0:99999:7:::
daemon:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
ntp:x:0:0:99999:7:::
dnsmasq:x:0:0:99999:7:::
logd:x:0:0:99999:7:::
ubus:x:0:0:99999:7:::
EOF
  chmod 600 "$SHADOW_OUTPUT"
}

if [ $# -lt 4 ] || [ $# -gt 5 ]; then
  usage
  exit 1
fi

SERVER_ADDRESS="$1"
WIFI_SSID="$2"
WIFI_PASSWORD="$3"
LUCI_PASSWORD="$4"
SERVER_NAME="${5:-speed.cloudflare.com}"

UUID="$(generate_uuid)"
SHORT_ID="$(generate_short_id)"
KEYS="$(generate_reality_keys)"
PRIVATE_KEY="$(printf '%s\n' "$KEYS" | sed -n '1p')"
PUBLIC_KEY="$(printf '%s\n' "$KEYS" | sed -n '2p')"
PASSWORD_HASH="$(generate_password_hash "$LUCI_PASSWORD")"

render_template "$SERVER_TEMPLATE" "$SERVER_OUTPUT" "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID"
render_template "$CLIENT_TEMPLATE" "$CLIENT_OUTPUT" "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID"
render_template "$ROUTER_TEMPLATE" "$ROUTER_OUTPUT" "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID"
generate_openwrt_defaults "$WIFI_SSID" "$WIFI_PASSWORD" "$PASSWORD_HASH"
generate_onexray_share "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PUBLIC_KEY" "$SHORT_ID"
generate_router_label "$WIFI_SSID" "$WIFI_PASSWORD" "$LUCI_PASSWORD"

cat <<EOF
Generated:
  - $SERVER_OUTPUT
  - $CLIENT_OUTPUT
  - $ROUTER_OUTPUT
  - $OPENWRT_OUTPUT
  - $SHADOW_OUTPUT
  - $ONEXRAY_SHARE_OUTPUT
  - $ONEXRAY_QR_OUTPUT
  - $ROUTER_LABEL_OUTPUT

Values:
  - UUID: $UUID
  - shortId: $SHORT_ID
EOF
