#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_TEMPLATE="$ROOT_DIR/server.example.json"
CLIENT_TEMPLATE="$ROOT_DIR/client.example.json"
ROUTER_TEMPLATE="$ROOT_DIR/openwrt/files/etc/xray/router.example.json"

SERVER_OUTPUT="$ROOT_DIR/server.json"
CLIENT_OUTPUT="$ROOT_DIR/client.json"
ROUTER_OUTPUT="$ROOT_DIR/openwrt/files/etc/xray/router.json"

usage() {
  cat <<'EOF' >&2
Usage:
  ./generate-configs.sh <server-address-or-domain> [server-name]

Arguments:
  server-address-or-domain  Xray server address used by client/router configs.
  server-name               REALITY SNI / camouflage name. Defaults to speed.cloudflare.com.

This generates:
  - server.json
  - client.json
  - openwrt/files/etc/xray/router.json
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
  private_key="$(printf '%s\n' "$output" | awk -F': ' '/^Private key:/ {print $2; exit}')"
  public_key="$(printf '%s\n' "$output" | awk -F': ' '/^Public key:/ {print $2; exit}')"

  if [ -z "$private_key" ] || [ -z "$public_key" ]; then
    echo "error: failed to parse xray x25519 output" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  printf '%s\n%s\n' "$private_key" "$public_key"
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

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  usage
  exit 1
fi

SERVER_ADDRESS="$1"
SERVER_NAME="${2:-speed.cloudflare.com}"
UUID="$(generate_uuid)"
SHORT_ID="$(generate_short_id)"
KEYS="$(generate_reality_keys)"
PRIVATE_KEY="$(printf '%s\n' "$KEYS" | sed -n '1p')"
PUBLIC_KEY="$(printf '%s\n' "$KEYS" | sed -n '2p')"

render_template "$SERVER_TEMPLATE" "$SERVER_OUTPUT" "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID"
render_template "$CLIENT_TEMPLATE" "$CLIENT_OUTPUT" "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID"
render_template "$ROUTER_TEMPLATE" "$ROUTER_OUTPUT" "$SERVER_ADDRESS" "$SERVER_NAME" "$UUID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$SHORT_ID"

cat <<EOF
Generated:
  - $SERVER_OUTPUT
  - $CLIENT_OUTPUT
  - $ROUTER_OUTPUT

Values:
  - UUID: $UUID
  - shortId: $SHORT_ID
EOF
