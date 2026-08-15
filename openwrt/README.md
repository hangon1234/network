# OpenWrt image layout for AX3000SE

This directory is meant to be copied into an OpenWrt Image Builder as `FILES=files`.

Target device:
- `iptime_ax3000se`

Recommended packages:
- `xray-core`
- `kmod-tun`
- `ca-bundle`

Build example:

```sh
make image \
  PROFILE="iptime_ax3000se" \
  PACKAGES="xray-core kmod-tun ca-bundle" \
  FILES="files"
```

Notes:
- `kmod-tun` is required for the `tun` inbound.
- The router config here uses `TUN` plus `autoSystemRoutingTable` and `autoOutboundsInterface` so the router can bootstrap the route automatically on Linux.
- If your WAN interface is unusual, you may need to change the outbound interface choice from `"auto"` to an explicit interface later.

