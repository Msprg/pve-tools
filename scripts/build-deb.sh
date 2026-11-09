#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# build-deb.sh <package-dir> <out-dir>
#
# Builds packages/<name>/ into <out-dir>/<name>_<version>_all.deb:
#   root/                  files installed as-is (git modes: 755 = executable, else 644)
#   debian/control         binary control fields without Version / Installed-Size
#   debian/changelog       Debian changelog; first entry gives name, version, timestamp
#   debian/{pre,post}{inst,rm}, debian/conffiles, debian/copyright
#   README.md              installed as /usr/share/doc/<name>/README.md
# File times are set to the changelog timestamp, so the same tree builds the same .deb.
set -euo pipefail

# packages built from another project's debian/ tree (see pvetools.conf) take the other path
if [ -f "${1:?package dir}/pvetools.conf" ]; then
    exec "$(dirname "$(readlink -f "$0")")/build-downstream.sh" "$@"
fi

pkgdir=$(readlink -f "${1:?package dir}")
mkdir -p "${2:?output dir}"
out=$(readlink -f "$2")
cl="$pkgdir/debian/changelog"
name=$(dpkg-parsechangelog -l "$cl" -S Source)
version=$(dpkg-parsechangelog -l "$cl" -S Version)
epoch=$(dpkg-parsechangelog -l "$cl" -S Timestamp)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -a "$pkgdir/root/." "$stage/"
doc="$stage/usr/share/doc/$name"
install -d "$stage/DEBIAN" "$doc"
install -m 0644 "$pkgdir/debian/copyright" "$doc/copyright"
gzip -9n < "$cl" > "$doc/changelog.gz"
[ -f "$pkgdir/README.md" ] && install -m 0644 "$pkgdir/README.md" "$doc/README.md"

# normalise permissions (umask / checkout independent)
find "$stage" -type d -exec chmod 0755 {} +
find "$stage" -type f -perm /u+x -exec chmod 0755 {} +
find "$stage" -type f ! -perm /u+x -exec chmod 0644 {} +

for s in preinst postinst prerm postrm; do
    [ -f "$pkgdir/debian/$s" ] && install -m 0755 "$pkgdir/debian/$s" "$stage/DEBIAN/$s"
done
[ -f "$pkgdir/debian/conffiles" ] && install -m 0644 "$pkgdir/debian/conffiles" "$stage/DEBIAN/conffiles"
if [ -f "$stage/DEBIAN/conffiles" ]; then
    while read -r f; do [ -z "$f" ] || [ -f "$stage$f" ] || { echo "conffile $f not in package" >&2; exit 1; }; done < "$stage/DEBIAN/conffiles"
fi

size=$(du -sk --apparent-size --exclude=DEBIAN "$stage" | cut -f1)
awk -v v="$version" -v s="$size" '
    NF == 0 { next }
    { print }
    /^Package:/ { print "Version: " v }
    END { print "Installed-Size: " s }' "$pkgdir/debian/control" > "$stage/DEBIAN/control"

(cd "$stage" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0 md5sum) \
    > "$stage/DEBIAN/md5sums"
chmod 0644 "$stage/DEBIAN/md5sums" "$stage/DEBIAN/control"

find "$stage" -exec touch -h -d "@$epoch" {} +
deb="$out/${name}_${version}_all.deb"
SOURCE_DATE_EPOCH=$epoch dpkg-deb --root-owner-group -Zxz --build "$stage" "$deb" >/dev/null
echo "$deb"
