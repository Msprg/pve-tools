#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# pkg-version.sh <package-dir>: the version pve-tools builds for that package.
#   native package (debian/changelog in the package dir): its changelog version
#   downstream package (pvetools.conf): <source changelog version>+pvetools<REVISION>
set -euo pipefail
pkgdir=${1:?package dir}
if [ -f "$pkgdir/pvetools.conf" ]; then
    conf() { sed -n "s/^$1=//p" "$pkgdir/pvetools.conf" | tail -n 1; }
    src="$pkgdir/$(conf SOURCE)"
    rev=$(conf REVISION)
    [[ $rev =~ ^[0-9]+$ ]] || { echo "bad REVISION '$rev' in $pkgdir/pvetools.conf" >&2; exit 1; }
    [ -f "$src/debian/changelog" ] || { echo "$src/debian/changelog missing - run: git submodule update --init" >&2; exit 1; }
    echo "$(dpkg-parsechangelog -l "$src/debian/changelog" -S Version)+pvetools$rev"
else
    dpkg-parsechangelog -l "$pkgdir/debian/changelog" -S Version
fi
