# pve-mods (pve-tools build)

[Meliox/PVE-mods](https://github.com/Meliox/PVE-mods) packaged from the fork
[Msprg/PVE-mods](https://github.com/Msprg/PVE-mods), so it installs and upgrades from the
pve-tools apt repository next to the other packages. **PVE 9.0+ only** (as upstream).

Upstream's mods, enabled individually with `pve-mods-configure`:

- `node_info` - temperatures, fans, GPU stats and history graphs, UPS, ZFS/SMART health and
  system info on the node summary page
- `nag_screen` - removes the subscription notice (don't combine with another no-nag patch,
  e.g. the community-scripts apt hook)

The mods patch PVE's web UI files. The package reverts and re-applies them across its own
upgrades, and can re-apply them after pve-manager upgrades (dpkg triggers; enable "Auto
re-patch on PVE upgrade" in the wizard). Full documentation: upstream's
[readme](https://github.com/Meliox/PVE-mods/blob/main/readme.md) and the per-mod readmes under
`source/src/modules/`.

## Install

```sh
apt install pve-mods        # from the pve-tools apt repository (see the top-level README)
pve-mods-configure          # pick and configure mods; then hard-refresh the browser (Ctrl+F5)
```

Packages some mods need (lm-sensors, nut-client, intel-gpu-tools, ...) are listed in each mod's
readme. Install on every node of a cluster, with the same configuration.

Versions are `<upstream version>+pvetools<N>`. They sort above upstream's own `.deb` of the
same version, so on a node that also has upstream's installer-installed package, apt replaces
it with this build - expected for a downstream build; use one source per node.

### PVE 7.x / 8.x

Not supported by v2. Upstream's archived v1 script works there; upstream points to the
revision of 2025-04-06 for these versions:

```sh
apt install lm-sensors && sensors-detect
wget https://raw.githubusercontent.com/Meliox/PVE-mods/51ab839c41950e2c65a6149eadf8633e3c55e2b5/pve-mod-gui-sensors.sh
bash pve-mod-gui-sensors.sh install
```

v1 patches files in place, so every pve-manager upgrade silently removes it - re-run `install`
after upgrades. Its `uninstall` restores the newest backup from `~/PVE-MODS`, which after an
upgrade is from the old pve-manager version: don't run `uninstall` on an upgraded node. Remove
v1 before installing v2 (`pve-mods-configure` refuses to run while v1 is installed).

## How this package is built

- `source/` is a git submodule: the **`pvetools` branch** of Msprg/PVE-mods, pinned to a
  commit. That branch is upstream's release tag plus any local changes; the fork's `main` is
  not used by this build.
- `pvetools.conf` sets the downstream revision (`REVISION`) and maintainer.
- `scripts/build-downstream.sh` exports the pinned tree, adds a changelog entry for
  `<upstream version>+pvetools<REVISION>`, runs upstream's own `build/gen-rules.sh` and
  `dpkg-buildpackage -b`. Locally that needs `dpkg-dev`, `debhelper` and `build-essential`.

### Changing the mods

1. Commit the change on the fork's `pvetools` branch (and open a PR upstream if it is generally
   useful).
2. In pve-tools: `git -C packages/pve-mods/source pull`, bump `REVISION` in `pvetools.conf`,
   commit (the submodule pin moves with the commit).
3. Tag and push `pve-mods-v<version>`, e.g. `pve-mods-v2.1.1+pvetools2` (`scripts/pkg-version.sh
   packages/pve-mods` prints it).

### Moving to a new upstream release

On the fork: fetch upstream's tags and merge the new release tag into `pvetools` (`git fetch
upstream --tags && git merge v2.2.0`), push. In pve-tools: update the submodule, set
`REVISION=1`, commit, tag `pve-mods-v2.2.0+pvetools1`.

## License

MIT, copyright Meliox and contributors - see `source/LICENSE`. Only the pve-tools build scripts
are GPL-3.0-or-later.
