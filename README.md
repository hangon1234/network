# Xray config templates

This repo keeps example templates in:

- `server.example.json`
- `client.example.json`
- `openwrt/templates/config.example.json`

Generate the real config files with:

```sh
./generate-configs.sh <server-address-or-domain> <wifi-ssid> <wifi-password> <luci-password> [server-name]
```

Run it on a machine that has `xray` in `PATH`, because the script uses `xray x25519` to create the REALITY keypair.
It also needs `python3` with `reportlab` available to generate the OneXray QR image.

## Install xray

`generate-configs.sh` needs the `xray` binary available in `PATH`.

### Linux

Use the official Xray install script:

```sh
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

Verify it:

```sh
xray version
xray x25519
```

### macOS

```sh
brew install xray
```

### OpenWrt

This repo expects `xray-core` to be installed through the OpenWrt image build. See [openwrt/README.md](openwrt/README.md).

That creates:

- `server.json`
- `client.json`
- `openwrt/files/etc/xray/config.json`
- `onexray-share.txt`
- `onexray-share.png`

The script fills in:

- `UUID`
- REALITY `privateKey` / `publicKey`
- `shortId`
- client/router server address
- optional REALITY SNI name
- a OneXray-compatible `vless://` share link
- a QR code image for importing into OneXray

For OpenWrt Wi-Fi and LuCI defaults, these are now generated as part of the main script:

```sh
./generate-configs.sh <server-address-or-domain> <wifi-ssid> <wifi-password> <luci-password> [server-name]
```

That generates `openwrt/files/etc/uci-defaults/99-xray` and `openwrt/files/etc/shadow`, which apply the Wi-Fi name/password and set the LuCI root password on first boot.

## Build OpenWrt image

If you want an OpenWrt image that already includes `xray-core`, `kmod-tun`, LuCI, SSH, and the repo's boot-time defaults, use the OpenWrt Image Builder and copy `openwrt/files` into it.

See [openwrt/README.md](openwrt/README.md) for the exact build steps and package list.
