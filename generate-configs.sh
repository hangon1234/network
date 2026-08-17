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
  ./generate-configs.sh server <server-address-or-domain> [server-name]
  ./generate-configs.sh router [wifi-ssid] [wifi-password] [luci-password] [luci-address]

Subcommands:
  server    Generate new REALITY key pair + UUID, write server.json and client.json.
            Must be run once before any router commands.

            Arguments:
              server-address-or-domain  Xray server address used by client/router configs.
              server-name               REALITY SNI / camouflage name.
                                        Defaults to speed.cloudflare.com.

            Generates:
              - server.json
              - client.json
              - onexray-share.txt
              - onexray-share.png

  router    Read credentials from existing server.json and generate router-specific
            configs. Run this once per router with that router's own SSID / passwords.
            server.json is never modified.

            Arguments (all optional — random/default values are used if omitted):
              wifi-ssid      Wi-Fi SSID.             Default: OpenWrt_<5 random hex chars>
              wifi-password  Wi-Fi password.         Default: 10 random hex chars
              luci-password  LuCI/SSH root password. Default: 10 random hex chars
              luci-address   Router LAN/LuCI IP.     Default: 192.168.1.1

            Generates:
              - openwrt/files/etc/xray/config.json
              - openwrt/files/etc/uci-defaults/99-xray
              - openwrt/files/etc/shadow
              - router-label.html (printable Wi-Fi label with QR code)
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

generate_random_hex() {
  local length="$1"   # number of hex characters (bytes = length/2, rounded up)
  local bytes=$(( (length + 1) / 2 ))

  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes" | cut -c1-"$length"
    return
  fi

  if [ -r /dev/urandom ]; then
    od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n' | cut -c1-"$length"
    printf '\n'
    return
  fi

  echo "error: unable to generate random hex; install openssl or expose /dev/urandom" >&2
  exit 1
}

generate_router_label() {
  local wifi_ssid="$1"
  local wifi_password="$2"
  local luci_password="$3"
  local luci_address="${4:-192.168.1.1}"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "warning: python3 not found, skipping router label HTML generation" >&2
    return
  fi

  python3 - "$wifi_ssid" "$wifi_password" "$luci_password" "$luci_address" "$ROUTER_LABEL_OUTPUT" <<'PY'
import sys
import base64
import html
from io import BytesIO

wifi_ssid, wifi_password, luci_password, luci_address, output_path = sys.argv[1:]

def escape_wifi_str(s):
    # Escape special characters for standard WIFI: URI format: \ ; , " :
    for ch in ('\\', ';', ',', ':', '"'):
        s = s.replace(ch, '\\' + ch)
    return s

wifi_payload = f"WIFI:T:WPA;S:{escape_wifi_str(wifi_ssid)};P:{escape_wifi_str(wifi_password)};;"

# Generate PNG QR code in memory
qr_b64 = ""
try:
    from reportlab.graphics.barcode import qr
    from reportlab.graphics import renderPM
    from reportlab.graphics.shapes import Drawing

    widget = qr.QrCodeWidget(wifi_payload)
    bounds = widget.getBounds()
    width = bounds[2] - bounds[0]
    height = bounds[3] - bounds[1]
    size = max(width, height)
    drawing = Drawing(size, size, transform=[size / width, 0, 0, size / height, 0, 0])
    drawing.add(widget)

    buf = BytesIO()
    renderPM.drawToFile(drawing, buf, fmt='PNG')
    qr_b64 = base64.b64encode(buf.getvalue()).decode('ascii')
except Exception as e:
    print(f"warning: failed to render QR code using reportlab: {e}", file=sys.stderr)

safe_ssid = html.escape(wifi_ssid)
safe_wifi_pw = html.escape(wifi_password)
safe_luci_addr = html.escape(luci_address)
safe_luci_pw = html.escape(luci_password)

qr_img_tag = f'<img class="qr-img" src="data:image/png;base64,{qr_b64}" alt="Wi-Fi QR Code" />' if qr_b64 else '<div class="no-qr">QR code unavailable</div>'

html_content = f"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Router Sticker Label - {safe_ssid}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Pretendard:wght@400;600;700&display=swap');

  :root {{
    --bg-page: #f1f3f5;
    --card-bg: #ffffff;
    --border-color: #222222;
    --text-main: #111111;
    --text-muted: #555555;
    --accent: #0969da;
  }}

  * {{
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }}

  body {{
    background-color: var(--bg-page);
    font-family: 'Pretendard', -apple-system, BlinkMacSystemFont, sans-serif;
    color: var(--text-main);
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 30px 15px;
  }}

  .actions {{
    margin-bottom: 20px;
    display: flex;
    gap: 12px;
  }}

  .btn {{
    background: #111827;
    color: #ffffff;
    border: none;
    padding: 10px 20px;
    font-size: 14px;
    font-weight: 600;
    border-radius: 6px;
    cursor: pointer;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    transition: background 0.2s;
  }}

  .btn:hover {{
    background: #374151;
  }}

  /* Sticker Label Container */
  .label-container {{
    display: flex;
    flex-direction: column;
    gap: 24px;
  }}

  .sticker-card {{
    background: var(--card-bg);
    width: 340px;
    border: 2px solid var(--border-color);
    border-radius: 12px;
    padding: 16px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.06);
    position: relative;
    page-break-inside: avoid;
  }}

  .header {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-bottom: 1.5px solid var(--border-color);
    padding-bottom: 8px;
    margin-bottom: 12px;
  }}

  .brand {{
    font-size: 15px;
    font-weight: 700;
    letter-spacing: -0.5px;
    display: flex;
    align-items: center;
    gap: 6px;
  }}

  .brand-badge {{
    background: #111827;
    color: #fff;
    font-size: 10px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: 4px;
    text-transform: uppercase;
  }}

  .sub {{
    font-size: 11px;
    color: var(--text-muted);
    font-weight: 500;
  }}

  .content-grid {{
    display: grid;
    grid-template-columns: 1fr 100px;
    gap: 12px;
    align-items: center;
  }}

  .info-group {{
    display: flex;
    flex-direction: column;
    gap: 8px;
  }}

  .field {{
    display: flex;
    flex-direction: column;
  }}

  .field-label {{
    font-size: 10px;
    text-transform: uppercase;
    font-weight: 700;
    color: var(--text-muted);
    letter-spacing: 0.5px;
    margin-bottom: 2px;
  }}

  .field-value {{
    font-family: 'JetBrains Mono', monospace;
    font-size: 13px;
    font-weight: 700;
    color: #000;
    background: #f8fafc;
    padding: 3px 6px;
    border: 1px solid #e2e8f0;
    border-radius: 4px;
    word-break: break-all;
    user-select: all;
  }}

  .qr-box {{
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: #ffffff;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 6px;
  }}

  .qr-img {{
    width: 90px;
    height: 90px;
    display: block;
    image-rendering: pixelated;
  }}

  .qr-caption {{
    font-size: 9px;
    font-weight: 600;
    color: var(--text-muted);
    margin-top: 4px;
    text-align: center;
  }}

  .divider {{
    height: 1px;
    background: #e2e8f0;
    margin: 12px 0;
  }}

  .admin-section {{
    background: #f8fafc;
    border: 1px dashed #cbd5e1;
    border-radius: 6px;
    padding: 8px 10px;
  }}

  .admin-title {{
    font-size: 10px;
    font-weight: 700;
    color: var(--text-muted);
    text-transform: uppercase;
    margin-bottom: 6px;
  }}

  .admin-grid {{
    display: flex;
    flex-direction: column;
    gap: 6px;
  }}

  .admin-grid .field-value {{
    background: #ffffff;
    font-size: 12px;
  }}

  /* Print specific adjustments */
  @media print {{
    body {{
      background: none;
      padding: 0;
      display: block;
    }}
    .actions {{
      display: none;
    }}
    .label-container {{
      gap: 16px;
    }}
    .sticker-card {{
      box-shadow: none;
      border: 1.5px solid #000;
      margin: 10px auto;
    }}
  }}
</style>
</head>
<body>

<div class="actions">
  <button class="btn" onclick="window.print()">🖨️ 라벨 인쇄 (Print Sticker)</button>
</div>

<div class="label-container">
  <div class="sticker-card">
    <div class="header">
      <div class="brand">
        <span>Router Access</span>
      </div>
      <div class="sub">Wi-Fi &amp; Admin Info</div>
    </div>

    <div class="content-grid">
      <div class="info-group">
        <div class="field">
          <span class="field-label">Wi-Fi SSID</span>
          <span class="field-value">{safe_ssid}</span>
        </div>
        <div class="field">
          <span class="field-label">Wi-Fi Password</span>
          <span class="field-value">{safe_wifi_pw}</span>
        </div>
      </div>

      <div class="qr-box">
        {qr_img_tag}
        <div class="qr-caption">Scan to Connect</div>
      </div>
    </div>

    <div class="divider"></div>

    <div class="admin-section">
      <div class="admin-title">Admin Management (LuCI / SSH)</div>
      <div class="admin-grid">
        <div class="field">
          <span class="field-label">LuCI URL (IP)</span>
          <span class="field-value">http://{safe_luci_addr}</span>
        </div>
        <div class="field">
          <span class="field-label">Root Password</span>
          <span class="field-value">{safe_luci_pw}</span>
        </div>
      </div>
    </div>
  </div>
</div>

</body>
</html>
"""

with open(output_path, "w", encoding="utf-8") as f:
    f.write(html_content)
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
  local lan_ip="${4:-192.168.1.1}"

  sed \
    -e "s|REPLACE_WITH_WIFI_SSID|$(escape_sed_replacement "$wifi_ssid")|g" \
    -e "s|REPLACE_WITH_WIFI_PASSWORD|$(escape_sed_replacement "$wifi_password")|g" \
    -e "s|REPLACE_WITH_ROOT_PASSWORD_HASH|$(escape_sed_replacement "$password_hash")|g" \
    -e "s|REPLACE_WITH_LAN_IP|$(escape_sed_replacement "$lan_ip")|g" \
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

# ---------------------------------------------------------------------------
# Parse server.json to extract the values written by the 'server' subcommand.
# ---------------------------------------------------------------------------
read_server_json() {
  if [ ! -f "$SERVER_OUTPUT" ]; then
    echo "error: $SERVER_OUTPUT not found. Run './generate-configs.sh server ...' first." >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required to parse server.json" >&2
    exit 1
  fi

  python3 - "$SERVER_OUTPUT" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    cfg = json.load(f)

inbound = cfg["inbounds"][0]
reality  = inbound["streamSettings"]["realitySettings"]

uuid        = inbound["settings"]["clients"][0]["id"]
private_key = reality["privateKey"]
short_ids   = [s for s in reality["shortIds"] if s]
short_id    = short_ids[0] if short_ids else ""
server_name = reality["serverNames"][0]

print(uuid)
print(private_key)
print(short_id)
print(server_name)
PY
}

# ---------------------------------------------------------------------------
# Read the server address from client.json (server.json has no address field).
# ---------------------------------------------------------------------------
read_server_address() {
  if [ ! -f "$CLIENT_OUTPUT" ]; then
    echo "error: $CLIENT_OUTPUT not found. Run './generate-configs.sh server ...' first." >&2
    exit 1
  fi

  python3 - "$CLIENT_OUTPUT" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
print(cfg["outbounds"][0]["settings"]["address"])
PY
}

# ---------------------------------------------------------------------------
# Derive the public key from an existing private key via xray x25519.
# ---------------------------------------------------------------------------
derive_public_key() {
  local private_key="$1"

  if ! command -v xray >/dev/null 2>&1; then
    echo "error: xray is required to derive the public key from the private key" >&2
    exit 1
  fi

  local output public_key
  output="$(xray x25519 -i "$private_key" 2>&1)"
  public_key="$(printf '%s\n' "$output" | awk -F': ' '
    /^Public key:/ {print $2; exit}
    /^Password \(PublicKey\):/ {print $2; exit}
  ')"

  if [ -z "$public_key" ]; then
    echo "error: failed to derive public key from private key" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  printf '%s\n' "$public_key"
}

# ---------------------------------------------------------------------------
# Subcommand: server
# ---------------------------------------------------------------------------
cmd_server() {
  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: ./generate-configs.sh server <server-address-or-domain> [server-name]" >&2
    exit 1
  fi

  local server_address="$1"
  local server_name="${2:-speed.cloudflare.com}"

  local uuid short_id keys private_key public_key
  uuid="$(generate_uuid)"
  short_id="$(generate_short_id)"
  keys="$(generate_reality_keys)"
  private_key="$(printf '%s\n' "$keys" | sed -n '1p')"
  public_key="$(printf '%s\n' "$keys" | sed -n '2p')"

  render_template "$SERVER_TEMPLATE" "$SERVER_OUTPUT" \
    "$server_address" "$server_name" "$uuid" "$private_key" "$public_key" "$short_id"

  render_template "$CLIENT_TEMPLATE" "$CLIENT_OUTPUT" \
    "$server_address" "$server_name" "$uuid" "$private_key" "$public_key" "$short_id"

  generate_onexray_share "$server_address" "$server_name" "$uuid" "$public_key" "$short_id"

  cat <<EOF
Generated:
  - $SERVER_OUTPUT
  - $CLIENT_OUTPUT
  - $ONEXRAY_SHARE_OUTPUT
  - $ONEXRAY_QR_OUTPUT

Values:
  - UUID:    $uuid
  - shortId: $short_id

Run './generate-configs.sh router [ssid] [wifi-pw] [luci-pw]' for each router to flash.
EOF
}

# ---------------------------------------------------------------------------
# Subcommand: router
# ---------------------------------------------------------------------------
cmd_router() {
  if [ $# -gt 4 ]; then
    echo "Usage: ./generate-configs.sh router [wifi-ssid] [wifi-password] [luci-password] [luci-address]" >&2
    exit 1
  fi

  local wifi_ssid="${1:-OpenWrt_$(generate_random_hex 5)}"
  local wifi_password="${2:-$(generate_random_hex 10)}"
  local luci_password="${3:-$(generate_random_hex 10)}"
  local luci_address="${4:-192.168.1.1}"

  # Read credentials from the already-generated server.json.
  local parsed uuid private_key short_id server_name
  parsed="$(read_server_json)"
  uuid="$(        printf '%s\n' "$parsed" | sed -n '1p')"
  private_key="$( printf '%s\n' "$parsed" | sed -n '2p')"
  short_id="$(    printf '%s\n' "$parsed" | sed -n '3p')"
  server_name="$( printf '%s\n' "$parsed" | sed -n '4p')"

  # server.json has no address field; read it from client.json.
  local server_address
  server_address="$(read_server_address)"

  # Derive the public key from the stored private key.
  local public_key
  public_key="$(derive_public_key "$private_key")"

  local password_hash
  password_hash="$(generate_password_hash "$luci_password")"

  render_template "$ROUTER_TEMPLATE" "$ROUTER_OUTPUT" \
    "$server_address" "$server_name" "$uuid" "$private_key" "$public_key" "$short_id"

  generate_openwrt_defaults "$wifi_ssid" "$wifi_password" "$password_hash" "$luci_address"
  generate_router_label "$wifi_ssid" "$wifi_password" "$luci_password" "$luci_address"

  cat <<EOF
Generated:
  - $ROUTER_OUTPUT
  - $OPENWRT_OUTPUT
  - $SHADOW_OUTPUT
  - $ROUTER_LABEL_OUTPUT

Values read from $SERVER_OUTPUT:
  - Server address: $server_address
  - Server name:    $server_name
  - UUID:           $uuid
  - shortId:        $short_id

Router credentials:
  - SSID:           $wifi_ssid
  - Wi-Fi password: $wifi_password
  - LuCI address:   http://$luci_address
  - LuCI password:  $luci_password

Printable label generated: $ROUTER_LABEL_OUTPUT
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
  usage
  exit 1
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  server) cmd_server "$@" ;;
  router) cmd_router "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  *)
    echo "error: unknown subcommand '$SUBCOMMAND'" >&2
    usage
    exit 1
    ;;
esac
