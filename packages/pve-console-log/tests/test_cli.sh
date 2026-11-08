#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests for the pve-console-log CLI helpers (sourced; temp files only, no PVE calls).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=SCRIPTDIR/../root/usr/sbin/pve-console-log
source "$HERE/../root/usr/sbin/pve-console-log"
set +e
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0; passes=0
eq() { if [ "$2" = "$3" ]; then passes=$((passes + 1)); printf '  ok   %s\n' "$1"; else fails=$((fails + 1)); printf '  FAIL %s\n       | got:  %s\n       | want: %s\n' "$1" "$2" "$3"; fi; }

echo "args handling:"
ours=$(mkargs 105 serial0)
eq "mkargs" "$ours" "-set chardev.serial0.logfile=/var/log/pve-console-105.serial0.log -set chardev.serial0.logappend=on"
eq "strip from empty" "$(strip_ours serial0 <<<"")" ""
eq "strip leaves only-ours empty" "$(strip_ours serial0 <<<"$ours")" ""
eq "strip keeps foreign args around ours" "$(strip_ours serial0 <<<"-cpu host $ours -smbios type=1,serial=x")" "-cpu host -smbios type=1,serial=x"
eq "strip other iface untouched" "$(strip_ours serial1 <<<"$ours")" "$ours"
two="$ours $(mkargs 105 serial1)"
eq "strip one of two ifaces" "$(strip_ours serial0 <<<"$two")" "$(mkargs 105 serial1)"

echo "CT config edits:"
f=$TMP/ct.conf
printf 'arch: amd64\nhostname: x\nparent: snap1\n\n[snap1]\narch: amd64\nlxc.console.logfile: /old\nsnaptime: 1\n' > "$f"
conf_add_key "$f" "lxc.console.logfile: /var/log/pve-console-5.console.log"
eq "add goes into the main section, before [snap1]" "$(awk '/^\[/{exit} /lxc.console/' "$f")" "lxc.console.logfile: /var/log/pve-console-5.console.log"
conf_del_key "$f" lxc.console.logfile
eq "del removes it from the main section" "$(awk '/^\[/{exit} /lxc.console/' "$f")" ""
eq "del leaves the snapshot section alone" "$(grep -c '^lxc.console.logfile: /old' "$f")" "1"
printf 'arch: amd64\nhostname: x' > "$TMP/nonl.conf"
conf_add_key "$TMP/nonl.conf" "lxc.console.logfile: /l"
eq "add to a file without trailing newline" "$(tail -n 2 "$TMP/nonl.conf" | tr '\n' '|')" "hostname: x|lxc.console.logfile: /l|"
eq "main_section stops at first [section]" "$(main_section "$f" | tail -n 1)" ""

echo "id validation:"
( check_ids 100 serial0 ) 2>/dev/null; eq "valid id" "$?" "0"
( check_ids 10x serial0 ) 2>/dev/null; eq "bad id rejected" "$?" "1"
( check_ids 100 serial9 ) 2>/dev/null; eq "bad iface rejected" "$?" "1"

echo "config parsing:"
CONF=$TMP/default; printf 'REPLAY_LINES=500\nREPLAY_LINES=600\n' > "$CONF"
eq "last value wins" "$(conf_value REPLAY_LINES 1000)" "600"
eq "missing key -> default" "$(conf_value REPLAY_VM yes)" "yes"

echo "$passes passed, $fails failed"
[ "$fails" = 0 ]
