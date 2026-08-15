# OpenWrt image layout for AX3000SE

This directory is meant to be copied into an OpenWrt Image Builder as `FILES=files`.

Target device:
- `iptime_ax3000se`

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

Notes:
- `kmod-tun` is required for the `tun` inbound.
- The router config here uses `TUN` plus `autoSystemRoutingTable` and `autoOutboundsInterface` so the router can bootstrap the route automatically on Linux.
- That `TUN` inbound is what captures traffic from the router itself and from LAN/Wi-Fi clients whose default gateway is this router.
- If your WAN interface is unusual, you may need to change the outbound interface choice from `"auto"` to an explicit interface later.
- The Wi-Fi defaults script uses `sae-mixed`, which is WPA2/WPA3 mixed mode.
- Use `./generate-openwrt.sh <wifi-ssid> <wifi-password> <luci-password>` from the repo root before building if you want the image to boot with your Wi-Fi name, Wi-Fi password, and LuCI root password already set.
- Stock OpenWrt uses `root` as the LuCI username. This repo sets the password automatically; changing the username is a different auth customization.
