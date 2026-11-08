#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# run-tests.sh <package-dir>: python unittests and shell tests under <package-dir>/tests
set -uo pipefail
t="${1:?package dir}/tests"
[ -d "$t" ] || { echo "no tests in $1"; exit 0; }
status=0
if compgen -G "$t/test_*.py" >/dev/null; then
    echo "== $t: python tests"
    python3 -m unittest discover -s "$t" -p 'test_*.py' || status=1
fi
for s in "$t"/test_*.sh; do
    [ -e "$s" ] || continue
    echo "== $s"
    bash "$s" || status=1
done
find "$t" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
exit $status
