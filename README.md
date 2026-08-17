# Xray config templates

This repo keeps example templates in:

- `server.example.json`
- `client.example.json`
- `openwrt/templates/config.example.json`

Config generation is split into two subcommands so that server credentials are
generated once and remain stable across multiple router flashes.

## Prerequisites

Both subcommands require `xray` in `PATH` (uses `xray x25519` for REALITY keys).
The `server` subcommand also requires `python3` with `reportlab` to generate the
OneXray QR image.

### Install xray — Linux

```sh
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
xray version
xray x25519   # smoke-test
```

### Install xray — macOS

```sh
brew install xray
```

### OpenWrt

`xray-core` is installed through the OpenWrt image build — see
[openwrt/README.md](openwrt/README.md).

---

## Step 1 — Generate server config (run once)

```sh
./generate-configs.sh server <server-address-or-domain> [server-name]
```

| Argument | Description |
|---|---|
| `server-address-or-domain` | Public IP or domain of the Xray server |
| `server-name` | REALITY SNI / camouflage hostname. Defaults to `speed.cloudflare.com` |

This generates a fresh UUID, REALITY key pair, and shortId, then writes:

- `server.json` — Xray inbound config for the server
- `client.json` — Xray outbound config for desktop/mobile clients
- `onexray-share.txt` — OneXray-compatible `vless://` share link
- `onexray-share.png` — QR code for importing into OneXray

> **Re-run `server` only when you want to rotate all credentials.**
> It will overwrite `server.json` and invalidate any previously flashed routers.

---

## Step 2 — Generate router config (run once per router)

```sh
./generate-configs.sh router [wifi-ssid] [wifi-password] [luci-password]
```

All arguments are **optional**. If omitted, random values are generated automatically:

| Argument | Default |
|---|---|
| `wifi-ssid` | `OpenWrt_<5 random hex chars>` e.g. `OpenWrt_a3f2c` |
| `wifi-password` | 10 random hex chars |
| `luci-password` | 10 random hex chars |

The script reads all Xray credentials (UUID, keys, shortId, server address)
from the existing `server.json` and `client.json` — **no new keys are generated**
and `server.json` is never modified.

Outputs:

- `openwrt/files/etc/xray/config.json` — Xray client config for the router
- `openwrt/files/etc/uci-defaults/99-xray` — UCI defaults script (applied on first boot)
- `openwrt/files/etc/shadow` — pre-hashed root password

### Multi-router workflow

```sh
# 1. Generate server credentials once
./generate-configs.sh server my.server.com

# 2. Flash router A
./generate-configs.sh router HomeNetwork_A wifi_pass_A luci_pass_A
#    → build OpenWrt image, flash router A

# 3. Flash router B  (server.json is untouched)
./generate-configs.sh router OfficeNetwork_B wifi_pass_B luci_pass_B
#    → build OpenWrt image, flash router B
```

---

## Build OpenWrt image

After running the `router` subcommand, use the OpenWrt Image Builder and copy
`openwrt/files` into it to produce a flashable image that already includes
`xray-core`, `kmod-tun`, LuCI, SSH, and the boot-time defaults.

See [openwrt/README.md](openwrt/README.md) for the exact build steps and package list.
