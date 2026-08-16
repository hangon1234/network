# Xray config templates

This repo keeps example templates in:

- `server.example.json`
- `client.example.json`
- `openwrt/files/etc/xray/router.example.json`

Generate the real config files with:

```sh
./generate-configs.sh <server-address-or-domain> [server-name]
```

Run it on a machine that has `xray` in `PATH`, because the script uses `xray x25519` to create the REALITY keypair.

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
- `openwrt/files/etc/xray/router.json`

The script fills in:

- `UUID`
- REALITY `privateKey` / `publicKey`
- `shortId`
- client/router server address
- optional REALITY SNI name

For OpenWrt Wi-Fi and LuCI defaults, run:

```sh
./generate-openwrt.sh <wifi-ssid> <wifi-password> <luci-password>
```

That generates `openwrt/files/etc/uci-defaults/99-xray`, which applies the Wi-Fi name/password and sets the LuCI root password on first boot.

## Build OpenWrt image

If you want an OpenWrt image that already includes `xray-core`, `kmod-tun`, LuCI, SSH, and the repo's boot-time defaults, use the OpenWrt Image Builder and copy `openwrt/files` into it.

See [openwrt/README.md](openwrt/README.md) for the exact build steps and package list.
