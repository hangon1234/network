# OpenWrt image layout for AX3000SE

This directory is meant to be copied into an OpenWrt Image Builder as `FILES=files`.

Target device:
- `iptime_ax3000se`

## How To Use

1. Download the OpenWrt Image Builder for the same OpenWrt release and target as your router.
2. Copy this directory into the Image Builder tree so it is available as `FILES=files`.
3. Build the image with the packages you need.
4. Flash the generated `*-sysupgrade.bin` from LuCI if the device is already running OpenWrt.

Recommended packages:
- `xray-core`
- `kmod-tun`
- `ca-bundle`
- `curl`
- `luci-ssl`
- `dropbear`
- `wpad-openssl` (or full `wpad`) for WPA2/WPA3 (SAE) mixed mode support

Build example:

```sh
make image \
  PROFILE="iptime_ax3000se" \
  PACKAGES="xray-core v2ray-geoip v2ray-geosite kmod-tun ca-bundle curl luci-ssl dropbear -wpad-basic-mbedtls -wpad-mini wpad-openssl" \
  FILES="files"
```

If your Image Builder profile pulls in a different `wpad-*` default, remove that one before adding `wpad-openssl` (or `wpad`). Note that `wpad-mini` and `wpad-basic-mbedtls` do not support WPA3 SAE and will cause hostapd to fail to start in `sae-mixed` mode.

If the device is already running OpenWrt, use the generated `*-sysupgrade.bin` in LuCI's firmware upgrade page. If you are installing OpenWrt for the first time from vendor firmware, use the factory image instead.

Notes:
- `kmod-tun` is required for the `tun` inbound.
- The router config here uses `TUN` plus `autoSystemRoutingTable` and `autoOutboundsInterface`, and the first-boot UCI script adds an `xray0` network interface plus default routes through it.
- That `TUN` inbound is what captures traffic from the router itself and from LAN/Wi-Fi clients whose default gateway is this router once routing is in place.
- If your WAN interface is unusual, you may need to change the outbound interface choice from `"auto"` to an explicit interface later.
- The Wi-Fi defaults script uses `sae-mixed`, which is WPA2/WPA3 mixed mode.
- `luci-ssl` gives you the LuCI web UI over HTTPS, and the overlayed `dropbear` config keeps SSH enabled on LAN port 22.
- Use `./generate-configs.sh <server-address-or-domain> <wifi-ssid> <wifi-password> <luci-password> [server-name]` from the repo root before building to generate all configs including the Wi-Fi name, Wi-Fi password, and LuCI root password already set.
- Stock OpenWrt uses `root` as the LuCI username. This repo sets the password automatically; changing the username is a different auth customization.
