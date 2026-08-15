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
- `wpad` for WPA2/WPA3 mixed mode and AP support

Build example:

```sh
make image \
  PROFILE="iptime_ax3000se" \
  PACKAGES="xray-core kmod-tun ca-bundle wpad" \
  FILES="files"
```

If the device is already running OpenWrt, use the generated `*-sysupgrade.bin` in LuCI's firmware upgrade page. If you are installing OpenWrt for the first time from vendor firmware, use the factory image instead.

Notes:
- `kmod-tun` is required for the `tun` inbound.
- The router config here uses `TUN` plus `autoSystemRoutingTable` and `autoOutboundsInterface`, and the first-boot UCI script adds an `xray0` network interface plus default routes through it.
- That `TUN` inbound is what captures traffic from the router itself and from LAN/Wi-Fi clients whose default gateway is this router once routing is in place.
- If your WAN interface is unusual, you may need to change the outbound interface choice from `"auto"` to an explicit interface later.
- The Wi-Fi defaults script uses `sae-mixed`, which is WPA2/WPA3 mixed mode.
- Use `./generate-openwrt.sh <wifi-ssid> <wifi-password> <luci-password>` from the repo root before building if you want the image to boot with your Wi-Fi name, Wi-Fi password, and LuCI root password already set.
- Stock OpenWrt uses `root` as the LuCI username. This repo sets the password automatically; changing the username is a different auth customization.
