# pve-tools

Add-ons for [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment), each
shipped as a Debian package from a signed apt repository, so they install, upgrade and
uninstall like the rest of the system - and survive PVE upgrades.

| Package | What it does |
|---|---|
| [pve-console-log](packages/pve-console-log/) | Persistent console scrollback: logs VM serial and CT consoles from guest start and replays the tail when you open the console in the web GUI, so it is no longer blank. |
| [pve-mods](packages/pve-mods/) | [Meliox/PVE-mods](https://github.com/Meliox/PVE-mods) (web UI mods: node sensors/GPU/UPS/storage health, no-nag), built from the fork [Msprg/PVE-mods](https://github.com/Msprg/PVE-mods). PVE 9.0+ only. |

## Install

On each PVE 8 or 9 node, as root:

```sh
curl -fsSL https://msprg.github.io/pve-tools/pve-tools-archive-keyring.gpg \
    -o /usr/share/keyrings/pve-tools-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/pve-tools-archive-keyring.gpg] https://msprg.github.io/pve-tools stable main" \
    > /etc/apt/sources.list.d/pve-tools.list
apt update
apt install pve-console-log
```

Check the key before trusting it:

```sh
gpg --show-keys /usr/share/keyrings/pve-tools-archive-keyring.gpg
# fingerprint must be: 46FC 63EC 1284 85C8 DB89 25B5 90B9 F73A 6B83 0C5F
```

The packages are `Architecture: all` and work on both Debian 12 (PVE 8) and Debian 13
(PVE 9), so there is a single `stable` suite. Each `.deb` is also attached to its
[GitHub release](https://github.com/Msprg/pve-tools/releases) for manual
`apt install ./<file>.deb`.

GitHub Pages caches files at its CDN for a few minutes; `apt update` right after a
release can report a hash mismatch - wait a few minutes and retry.

## Building from source

```sh
git clone --recurse-submodules https://github.com/Msprg/pve-tools.git
make lint test build      # needs shellcheck, dpkg-dev, apt-utils, debhelper; python3-pyte for the full test run
sudo make repo-smoke      # builds a throwaway signed repo and checks it with apt (isolated apt state)
```

Layout:

- `packages/<name>/root/` - files as installed; `debian/` - control, changelog,
  maintainer scripts; `tests/` - run by `make test`
- `packages/<name>/pvetools.conf` + `source/` submodule - a package built from another
  project's own `debian/` tree (downstream build, version `<upstream>+pvetools<N>`)
- `scripts/` - `build-deb.sh` (reproducible: file times come from the changelog),
  `build-apt-repo.sh`, `repo-smoke-test.sh`, `lint.sh`, `run-tests.sh`
- `pages/` - static files for the apt repository site (the `gh-pages` branch)

## Releasing

1. Own packages: add an entry to `packages/<name>/debian/changelog`. Downstream packages:
   move the submodule and/or bump `REVISION` in `pvetools.conf` (see the package README).
2. Commit, then tag and push the version `scripts/pkg-version.sh packages/<name>` prints:
   `git tag <name>-v<version> && git push origin <name>-v<version>`.

The [release workflow](.github/workflows/release.yml) checks the tag against the
changelog, runs the tests, builds the `.deb`, adds it to the apt repository on
`gh-pages`, re-signs it with the `APT_SIGNING_KEY` secret, verifies it with apt,
publishes it and creates the GitHub release. Published versions are never replaced.

## Other add-ons

See [THIRD-PARTY.md](THIRD-PARTY.md) for add-ons by other authors that work well
alongside these and are not packaged here.

## License

[GPL-3.0-or-later](LICENSE), except packages built from other projects, which keep their own
license (`packages/pve-mods/source`: MIT, Meliox and contributors).
