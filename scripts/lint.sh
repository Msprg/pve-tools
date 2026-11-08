#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# lint.sh: shellcheck every tracked shell script, byte-compile every tracked python script.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SHELLCHECK=${SHELLCHECK:-shellcheck}
status=0
while IFS= read -r f; do
    first=$(head -n 1 "$f" 2>/dev/null)
    case "$first" in
        '#!/bin/sh'*|'#!/bin/bash'*|'#!/usr/bin/env bash'*)
            "$SHELLCHECK" -x "$f" || status=1 ;;
        '#!/usr/bin/python3'*|'#!/usr/bin/env python3'*)
            python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$f" || status=1 ;;
    esac
done < <(git ls-files)
[ "$status" = 0 ] && echo "lint: ok"
exit $status
