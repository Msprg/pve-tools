# Third-party Proxmox VE add-ons

Add-ons by other authors that the maintainer of pve-tools runs alongside it and that are
**not** packaged in this repository; install them from their upstream, ideally pinned to
a commit you have read. Pins below were checked on 2026-11-08.

## Web UI mods - Meliox/PVE-mods

Now packaged in this repository as [`pve-mods`](packages/pve-mods/) (built from the fork
Msprg/PVE-mods; PVE 9.0+). The package README also covers the archived v1 script for PVE 7/8.

## Subscription notice removal - community-scripts/ProxmoxVE

<https://github.com/community-scripts/ProxmoxVE> - MIT license.
`tools/pve/post-pve-install.sh` (among other post-install choices) installs
`/usr/local/bin/pve-remove-nag.sh` plus an apt `DPkg::Post-Invoke` hook
(`/etc/apt/apt.conf.d/no-nag-script`) that re-applies the patch to
`proxmoxlib.js` after every package operation, so it survives upgrades.

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/11acd8db754db96c9088762e2deff9c16f0a35f7/tools/pve/post-pve-install.sh)"
```
