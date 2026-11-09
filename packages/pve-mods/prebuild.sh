#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# prebuild.sh <source-tree> <package-version>
# Called by scripts/build-downstream.sh on the exported tree before upstream's build steps.
# Mirrors upstream's release workflow ("Inject version into Config.pm"): the source carries
# 'version-placeholder', which upstream's CI replaces with the release version.
set -euo pipefail
tree=${1:?source tree} version=${2:?version}
f="$tree/src/modules/node_info/files/Config.pm"
grep -qF "= 'version-placeholder';" "$f" \
    || { echo "prebuild: version placeholder not found in $f - check upstream's release workflow" >&2; exit 1; }
BUILD_VERSION=$version perl -i -pe 'BEGIN { $v = $ENV{BUILD_VERSION} }
    s/(our \$VERSION\s*=\s*'"'"')[^'"'"']*'"'"';/${1}$v'"'"';/' "$f"
grep -qF "= '$version';" "$f" || { echo "prebuild: version injection failed" >&2; exit 1; }
