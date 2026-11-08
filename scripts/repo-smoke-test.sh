#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# repo-smoke-test.sh <dir-with-debs> [repo-url keyring]
#
# Without a URL: builds a repo from the .debs in a temp dir, signed with a throwaway key,
# and checks it with apt over file://. With a URL and keyring: checks that published repo.
# apt runs with its own lists/cache/sources dirs, so the host's apt state is not touched.
# Needs root (apt-get update).
set -euo pipefail

debs=$(readlink -f "${1:?dir with .debs}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lists/partial" "$T/cache/archives/partial" "$T/empty"

if [ $# -ge 3 ]; then
    url=$2 keyring=$(readlink -f "$3")
else
    export GNUPGHOME="$T/gnupg"; mkdir -m 0700 "$GNUPGHOME"
    gpg --batch --quiet --passphrase '' --quick-gen-key "pve-tools smoke test <smoke@invalid>" ed25519 sign never
    SIGNING_KEY=$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print $10; exit}')
    export SIGNING_KEY
    mkdir -p "$T/site/pool/main"
    cp "$debs"/*.deb "$T/site/pool/main/"
    "$(dirname "$0")/build-apt-repo.sh" "$T/site"
    chmod -R a+rX "$T"
    url="file://$T/site" keyring="$T/site/pve-tools-archive-keyring.gpg"
fi

echo "deb [signed-by=$keyring] $url stable main" > "$T/sources.list"
apt_opts=(-o Dir::Etc::SourceList="$T/sources.list" -o Dir::Etc::SourceParts="$T/empty"
          -o Dir::Etc::TrustedParts="$T/empty" -o Dir::Etc::Trusted="$T/none"
          -o Dir::State::Lists="$T/lists" -o Dir::Cache="$T/cache" -o Acquire::Languages=none
          -o APT::Get::List-Cleanup=0 -o Debug::NoLocking=1 -o APT::Sandbox::User=root)
apt-get "${apt_opts[@]}" -q update 2>&1 | tee "$T/update.log"
if grep -qiE '^(W|E):|NO_PUBKEY|not signed|is not valid|InRelease.*(BADSIG|EXPKEYSIG)' "$T/update.log"; then
    echo "FAIL: apt update reported problems" >&2; exit 1
fi
status=0
for deb in "$debs"/*.deb; do
    name=$(dpkg-deb -f "$deb" Package) ver=$(dpkg-deb -f "$deb" Version)
    cand=$(apt-cache "${apt_opts[@]}" policy "$name" | awk '/Candidate:/ {print $2}')
    have=$(apt-cache "${apt_opts[@]}" madison "$name" | awk -v v="$ver" '$3 == v' | head -n 1)
    if [ -n "$have" ]; then
        if (cd "$T" && apt-get "${apt_opts[@]}" -q download "$name=$ver" >/dev/null) \
                && cmp -s "$T/${name}_${ver}_all.deb" "$deb"; then
            echo "ok   $name $ver: listed (candidate $cand), downloads, signature + hash verified"
        else
            echo "FAIL $name $ver: download/verify failed"; status=1
        fi
    else
        echo "FAIL $name $ver: not in the repo"; status=1
    fi
done
exit $status
