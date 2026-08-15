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
