#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# build-apt-repo.sh <site-dir>
#
# (Re)generates a signed apt repository in <site-dir> from the .debs under
# <site-dir>/pool/:  dists/stable/main/binary-{amd64,arm64}/Packages(.gz),
# dists/stable/{Release,InRelease,Release.gpg}, and the public key files
# pve-tools-archive-keyring.gpg (binary, for signed-by=) and pve-tools-archive-keyring.asc.
# The packages are Architecture: all; they are listed in each arch's Packages file
# (the classic layout every apt version understands).
#
# Signing: SIGNING_KEY=<fingerprint>, with its secret key in gpg's keyring ($GNUPGHOME).
set -euo pipefail

site=$(readlink -f "${1:?site dir}")
key=${SIGNING_KEY:?set SIGNING_KEY to the signing key fingerprint}
suite=stable comp=main archs="amd64 arm64"

cd "$site"
[ -d pool ] || { echo "no pool/ in $site" >&2; exit 1; }
rm -rf "dists/$suite"
for a in $archs; do
    d="dists/$suite/$comp/binary-$a"
    mkdir -p "$d"
    apt-ftparchive --arch "$a" packages pool > "$d/Packages"
    gzip -9n < "$d/Packages" > "$d/Packages.gz"
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=pve-tools \
    -o APT::FTPArchive::Release::Label=pve-tools \
    -o APT::FTPArchive::Release::Suite="$suite" \
    -o APT::FTPArchive::Release::Codename="$suite" \
    -o APT::FTPArchive::Release::Architectures="$archs" \
    -o APT::FTPArchive::Release::Components="$comp" \
    -o APT::FTPArchive::Release::Description="pve-tools: add-ons for Proxmox VE (https://github.com/Msprg/pve-tools)" \
    release "dists/$suite" > "$tmp"
mv "$tmp" "dists/$suite/Release"

gpg --batch --yes --local-user "$key" --digest-algo SHA512 --clearsign \
    -o "dists/$suite/InRelease" "dists/$suite/Release"
gpg --batch --yes --local-user "$key" --digest-algo SHA512 --armor --detach-sign \
    -o "dists/$suite/Release.gpg" "dists/$suite/Release"
gpg --batch --yes --export "$key" > pve-tools-archive-keyring.gpg
gpg --batch --yes --armor --export "$key" > pve-tools-archive-keyring.asc
touch .nojekyll

echo "repo: $(grep -c '^Package:' "dists/$suite/$comp/binary-amd64/Packages") package version(s) in $site"
