#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# release-notes.sh <package-dir>: markdown release notes for the GitHub release.
set -euo pipefail
pkgdir=${1:?package dir}
if [ -f "$pkgdir/pvetools.conf" ]; then
    conf() { sed -n "s/^$1=//p" "$pkgdir/pvetools.conf" | tail -n 1; }
    src="$pkgdir/$(conf SOURCE)"
    commit=$(git -C "$src" rev-parse HEAD)
    uv=$(dpkg-parsechangelog -l "$src/debian/changelog" -S Version)
    echo "pve-tools build of [$(conf UPSTREAM) $uv](https://github.com/$(conf UPSTREAM)/releases/tag/v$uv),"
    echo "from [$(conf FORK)@${commit:0:12}](https://github.com/$(conf FORK)/tree/$commit)."
else
    dpkg-parsechangelog -l "$pkgdir/debian/changelog" -S Changes | tail -n +4 | sed 's/^  //'
fi
printf '\nInstall from the apt repository: https://msprg.github.io/pve-tools/\n'
