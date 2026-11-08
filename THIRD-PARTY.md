# Third-party Proxmox VE add-ons

Add-ons by other authors that the maintainer of pve-tools runs alongside it. They are
**not** copied into this repository; install them from their upstream, ideally pinned to
a commit you have read. Pins below were checked on 2026-11-08.

## Web UI mods - Meliox/PVE-mods

<https://github.com/Meliox/PVE-mods> - MIT license (added upstream 2026-10-11).
Since v2 this is itself a Debian package, `pve-mods`, for **PVE 9.0+**. Its mods are
enabled individually with the `pve-mods-configure` wizard:

- `node_info` - CPU/NVMe/HDD/SSD/RAM temperatures, fans, GPU stats and history
  graphs, UPS status, ZFS/SMART health and system info on the node summary page
- `nag_screen` - removes the subscription notice (overlaps with the community-scripts
  hook below; use one of the two)
- `oidc_console_access` - lets selected (e.g. OIDC-synced) groups use the node Shell /
  Upgrade console
- `guest_info` - merged VM/CT summary graphs with pressure stall information

The mods patch PVE's web UI files; the package can re-apply them automatically after
a pve-manager upgrade (dpkg triggers, option in the wizard). Install from upstream's
releases (the installer downloads the latest `.deb` and checks its SHA256 sum):

```sh
curl -sL https://raw.githubusercontent.com/Meliox/PVE-mods/refs/heads/main/install.sh | bash
pve-mods-configure
```

**PVE 7.x/8.x**: only the archived, unmaintained v1 scripts work there; upstream
points to the revision of 2025-04-06 for these versions:

```sh
apt install lm-sensors && sensors-detect
wget https://raw.githubusercontent.com/Meliox/PVE-mods/51ab839c41950e2c65a6149eadf8633e3c55e2b5/pve-mod-gui-sensors.sh
bash pve-mod-gui-sensors.sh install
```

v1 patches files in place, so **every pve-manager upgrade silently removes it** -
re-run `install` after upgrades. Its `uninstall` restores the newest backup from
`~/PVE-MODS`, which after an upgrade is from the old pve-manager version: do not run
`uninstall` on an already-upgraded node. Remove v1 before installing v2 (v2's wizard
refuses to run while v1 is installed).

## Subscription notice removal - community-scripts/ProxmoxVE

<https://github.com/community-scripts/ProxmoxVE> - MIT license.
`tools/pve/post-pve-install.sh` (among other post-install choices) installs
`/usr/local/bin/pve-remove-nag.sh` plus an apt `DPkg::Post-Invoke` hook
(`/etc/apt/apt.conf.d/no-nag-script`) that re-applies the patch to
`proxmoxlib.js` after every package operation, so it survives upgrades.

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/11acd8db754db96c9088762e2deff9c16f0a35f7/tools/pve/post-pve-install.sh)"
```
