# Third-party Proxmox VE add-ons

Add-ons by other authors that the maintainer of pve-tools runs alongside it. They are
**not** copied into this repository; install them from their upstream, ideally pinned to
a commit you have read. Pins below were current on 2026-11-08.

## Node sensor readings in the web UI - Meliox/PVE-mods

<https://github.com/Meliox/PVE-mods> - MIT license (added upstream 2026-10-11).
Shows CPU/disk/RAM temperatures, fan speeds, UPS state and system info on the node
summary page by patching `/usr/share/pve-manager/js/pvemanagerlib.js` and
`/usr/share/perl5/PVE/API2/Nodes.pm` in place.

```sh
apt install lm-sensors && sensors-detect
wget https://raw.githubusercontent.com/Meliox/PVE-mods/b89abb21f4e4f7224e0113c7c70d71c34317f830/pve-mod-gui-sensors.sh
bash pve-mod-gui-sensors.sh install
```

Upstream tests against PVE 9.x; for 7.x/8.x its README points to an older revision.
Being an in-place patch, **every pve-manager upgrade silently removes it** - re-run
`install` after upgrades. Its `uninstall` restores the *newest backup* from
`~/PVE-MODS`; after an upgrade that backup is from the old pve-manager version, so do
not run `uninstall` on an already-upgraded node.

## Subscription notice removal - community-scripts/ProxmoxVE

<https://github.com/community-scripts/ProxmoxVE> - MIT license.
`tools/pve/post-pve-install.sh` (among other post-install choices) installs
`/usr/local/bin/pve-remove-nag.sh` plus an apt `DPkg::Post-Invoke` hook
(`/etc/apt/apt.conf.d/no-nag-script`) that re-applies the patch to
`proxmoxlib.js` after every package operation, so it survives upgrades.

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/11acd8db754db96c9088762e2deff9c16f0a35f7/tools/pve/post-pve-install.sh)"
```
