#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# build-downstream.sh <package-dir> <out-dir>
#
# Builds a package whose source is another project's debhelper tree (a git submodule,
# see <package-dir>/pvetools.conf) - e.g. pve-mods from the fork of Meliox/PVE-mods:
#   - exports the submodule's committed tree (local edits are ignored, so builds match the pin)
#   - adds a changelog entry for <upstream version>+pvetools<REVISION>, and makes us the
#     Maintainer (the original one is kept as XSBC-Original-Maintainer)
#   - runs <package-dir>/prebuild.sh <tree> <version> if present (steps upstream's release CI
#     does before building), then upstream's build/gen-rules.sh >> debian/rules (when present)
#     and dpkg-buildpackage -b
# Prints the path of the built .deb on stdout; build output goes to stderr.
set -euo pipefail

pkgdir=$(readlink -f "${1:?package dir}")
mkdir -p "${2:?output dir}"
out=$(readlink -f "$2")
here=$(dirname "$(readlink -f "$0")")
conf() { sed -n "s/^$1=//p" "$pkgdir/pvetools.conf" | tail -n 1; }
src="$pkgdir/$(conf SOURCE)"

[ -f "$src/debian/rules" ] || { echo "$src has no debian/rules - run: git submodule update --init" >&2; exit 1; }
if ! command -v dpkg-buildpackage >/dev/null \
        || ! dpkg-query -W -f='${Status}' debhelper 2>/dev/null | grep -q 'ok installed' \
        || ! dpkg-query -W -f='${Status}' build-essential 2>/dev/null | grep -q 'ok installed'; then
    echo "building $(basename "$pkgdir") needs dpkg-dev, debhelper and build-essential (apt install dpkg-dev debhelper build-essential)" >&2
    exit 1
fi

version=$("$here/pkg-version.sh" "$pkgdir")
name=$(dpkg-parsechangelog -l "$src/debian/changelog" -S Source)
commit=$(git -C "$src" rev-parse HEAD)
epoch=$(git -C "$src" log -1 --format=%ct HEAD)
upstream_version=$(dpkg-parsechangelog -l "$src/debian/changelog" -S Version)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$src" archive --format=tar --prefix="$name/" HEAD | tar -C "$work" -xf -
cd "$work/$name"

{
    printf '%s (%s) stable; urgency=medium\n\n' "$name" "$version"
    printf '  * pve-tools build of %s %s from %s@%s.\n\n' "$(conf UPSTREAM)" "$upstream_version" "$(conf FORK)" "${commit:0:12}"
    printf ' -- %s  %s\n\n' "$(conf MAINTAINER)" "$(LC_ALL=C date -R -u -d "@$epoch")"
    cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog

awk -v m="$(conf MAINTAINER)" '
    !done && /^Maintainer:/ { print "Maintainer: " m; sub(/^Maintainer:/, "XSBC-Original-Maintainer:"); done = 1 }
    { print }' debian/control > debian/control.new
mv debian/control.new debian/control

# package-specific steps upstream's own release workflow performs before building
if [ -x "$pkgdir/prebuild.sh" ]; then
    "$pkgdir/prebuild.sh" "$work/$name" "$version" >&2
fi
if [ -f build/gen-rules.sh ]; then
    bash build/gen-rules.sh >> debian/rules
fi
SOURCE_DATE_EPOCH=$epoch dpkg-buildpackage -us -uc -b >&2

deb="../${name}_${version}_all.deb"
[ -f "$deb" ] || { echo "dpkg-buildpackage did not produce $deb" >&2; exit 1; }
cp "$deb" "$out/"
echo "$out/$(basename "$deb")"
