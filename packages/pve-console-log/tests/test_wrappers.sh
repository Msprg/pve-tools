#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests for the qm and dtach wrappers. Each runs from a sandbox copy whose paths
# (REAL, RENDER, CONF, LOGDIR) point into a temp dir; `script` provides the tty
# the GUI's termproxy would. Nothing on the host is touched.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="$HERE/../root"
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
fails=0; passes=0

ok()   { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       | /'; }
expect() { # name haystack needle
    if grep -qF -- "$3" <<<"$2"; then ok "$1"; else fail "$1" "$2"; fi
}
expect_not() {
    if grep -qF -- "$3" <<<"$2"; then fail "$1" "$2"; else ok "$1"; fi
}
tty_run() { # cmd...  -> combined output with a pty on stdin/stdout, CR stripped
    script -qec "$(printf '%q ' "$@")" /dev/null 2>&1 | tr -d '\r'
}

mkdir -p "$SB/log" "$SB/lib"
cat > "$SB/real-qm" <<'S'
#!/bin/sh
printf 'REAL-QM'; for a in "$@"; do printf ' [%s]' "$a"; done; echo
exit 7
S
cat > "$SB/real-dtach" <<'S'
#!/bin/sh
printf '\033[H\033[J'; echo "REAL-DTACH attached"; sleep 1.5; echo "LIVE-FROM-CT"
S
printf '#!/bin/sh\nsleep 30\n' > "$SB/lib/hang"
printf '#!/bin/sh\necho "RENDER $*"\n' > "$SB/lib/render-stub"
cp "$ROOT/usr/lib/pve-console-log/pve-console-replay" "$SB/lib/pve-console-replay"
chmod +x "$SB"/real-* "$SB"/lib/*
printf 'boot line 1\r\nguest login: \r\n' > "$SB/log/pve-console-100.serial0.log"
printf 'ct boot\r\nct login: \r\n' > "$SB/log/pve-console-200.console.log"
printf 'REPLAY_LINES=1000\nREPLAY_VM=yes\nREPLAY_CT=yes\n' > "$SB/conf"

mkwrap() { # src name real render conf
    sed -e "s#^REAL=.*#REAL=$3#" -e "s#^RENDER=.*#RENDER=$4#" -e "s#^CONF=.*#CONF=$5#" \
        -e "s#^LOGDIR=.*#LOGDIR=$SB/log#" "$ROOT/$1" > "$SB/$2"
    chmod +x "$SB/$2"
}
mkwrap usr/sbin/qm qm "$SB/real-qm" "$SB/lib/pve-console-replay" "$SB/conf"
mkwrap usr/bin/dtach dtach "$SB/real-dtach" "$SB/lib/pve-console-replay" "$SB/conf"

echo "qm wrapper:"
out=$(tty_run "$SB/qm" terminal 100 -escape 0 -iface serial0)
expect "terminal on a tty replays, then execs the real qm" "$out" "--- replay: last 2 lines"
expect "  ...with the log content" "$out" "guest login:"
expect "  ...and passes all arguments through" "$out" "REAL-QM [terminal] [100] [-escape] [0] [-iface] [serial0]"
check() { # name condition-command...
    local name=$1; shift
    if "$@"; then ok "$name"; else fail "$name" "${out:-}"; fi
}
check "  ...replay comes before the live console" \
    [ "$(grep -n -- '--- end of replay' <<<"$out" | cut -d: -f1)" -lt "$(grep -n REAL-QM <<<"$out" | cut -d: -f1)" ]
out=$(tty_run "$SB/qm" terminal 100 -escape 0)
expect "default interface is serial0" "$out" "--- replay:"
out=$(tty_run "$SB/qm" terminal 101 -escape 0)
expect_not "no log for that VM -> no replay" "$out" "--- replay"
out=$(tty_run "$SB/qm" start 100)
expect_not "other subcommands are untouched" "$out" "--- replay"
expect "  ...and still exec" "$out" "REAL-QM [start] [100]"
out=$("$SB/qm" terminal 100 -iface serial0 </dev/null 2>&1 | cat)
expect_not "no tty -> no replay" "$out" "--- replay"
for bad in '../../etc/passwd' '100x' ''; do
    out=$(tty_run "$SB/qm" terminal "$bad" -iface serial0)
    expect_not "hostile vmid '$bad' -> no replay" "$out" "--- replay"
done
out=$(tty_run "$SB/qm" terminal 100 -iface ../../x)
expect_not "hostile iface -> no replay" "$out" "--- replay"
"$SB/qm" status 100 >/dev/null 2>&1; rc=$?
check "exit status of the real qm is preserved (got $rc)" [ "$rc" = 7 ]
# shellcheck disable=SC2016  # the literal $HOME is the point
out=$(tty_run "$SB/qm" set 100 --description 'two words "quoted" $HOME')
# shellcheck disable=SC2016
expect "arguments with spaces/quotes/dollars pass through verbatim" "$out" '[two words "quoted" $HOME]'

printf 'REPLAY_VM=no\n' > "$SB/conf-novm"
mkwrap usr/sbin/qm qm-novm "$SB/real-qm" "$SB/lib/pve-console-replay" "$SB/conf-novm"
out=$(tty_run "$SB/qm-novm" terminal 100 -iface serial0)
expect_not "REPLAY_VM=no disables the replay" "$out" "--- replay"
expect "  ...but the console still opens" "$out" "REAL-QM [terminal]"

printf 'REPLAY_LINES=1\n' > "$SB/conf-1"
mkwrap usr/sbin/qm qm-1 "$SB/real-qm" "$SB/lib/pve-console-replay" "$SB/conf-1"
out=$(tty_run "$SB/qm-1" terminal 100 -iface serial0)
expect "REPLAY_LINES is honoured" "$out" "--- replay: last 1 lines"

# shellcheck disable=SC2016  # shell syntax in the config must stay inert: it is parsed, never sourced
printf '\x00\xff garbage ((( $(rm -rf /) `x`\nREPLAY_LINES=abc\nREPLAY_VM\n' > "$SB/conf-broken"
mkwrap usr/sbin/qm qm-broken "$SB/real-qm" "$SB/lib/pve-console-replay" "$SB/conf-broken"
out=$(tty_run "$SB/qm-broken" terminal 100 -iface serial0)
expect "broken config file: still replays with defaults" "$out" "--- replay: last 2 lines"
expect "  ...and still execs the real qm" "$out" "REAL-QM [terminal]"
mkwrap usr/sbin/qm qm-noconf "$SB/real-qm" "$SB/lib/pve-console-replay" "$SB/does-not-exist"
out=$(tty_run "$SB/qm-noconf" terminal 100 -iface serial0)
expect "missing config file: defaults" "$out" "--- replay:"

mkwrap usr/sbin/qm qm-norender "$SB/real-qm" "$SB/lib/missing" "$SB/conf"
out=$(tty_run "$SB/qm-norender" terminal 100 -iface serial0)
expect_not "missing renderer -> no replay" "$out" "--- replay"
expect "  ...console still opens" "$out" "REAL-QM [terminal]"
mkwrap usr/sbin/qm qm-hang "$SB/real-qm" "$SB/lib/hang" "$SB/conf"
start=$(date +%s)
out=$(tty_run "$SB/qm-hang" terminal 100 -iface serial0)
took=$(( $(date +%s) - start ))
expect "hanging renderer -> console still opens" "$out" "REAL-QM [terminal]"
check "  ...after the 3 s timeout (${took}s)" [ "$took" -le 5 ]

echo "dtach wrapper:"
out=$(tty_run "$SB/dtach" -A /var/run/dtach/vzctlconsole200 -r winch -z lxc-console -n 200 -t 0 -e -1)
expect "GUI console shape replays" "$out" "--- replay: last 2 lines"
a=$(grep -n "REAL-DTACH attached" <<<"$out" | cut -d: -f1); r=$(grep -n -- "--- replay" <<<"$out" | cut -d: -f1)
l=$(grep -n "LIVE-FROM-CT" <<<"$out" | cut -d: -f1)
ordered() { [ -n "$a" ] && [ -n "$r" ] && [ -n "$l" ] && [ "$a" -lt "$r" ] && [ "$r" -lt "$l" ]; }
check "  ...after dtach's clear-screen, before live output" ordered
out=$(tty_run "$SB/dtach" -A /var/run/dtach/vzctlconsole200 -r winch -z lxc-attach --clear-env -n 200)
expect_not "cmode=shell (lxc-attach) -> no replay" "$out" "--- replay"
out=$(tty_run "$SB/dtach" -A /var/run/dtach/vzctlconsole201 -r winch -z lxc-console -n 201)
expect_not "CT without log -> no replay" "$out" "--- replay"
out=$(tty_run "$SB/dtach" -A /tmp/other.sock -z bash)
expect_not "non-PVE dtach use -> no replay" "$out" "--- replay"
expect "  ...and still execs" "$out" "REAL-DTACH attached"
out=$(tty_run "$SB/dtach" -A /var/run/dtach/vzctlconsole../x -z lxc-console)
expect_not "hostile socket path -> no replay" "$out" "--- replay"
printf 'REPLAY_CT=no\n' > "$SB/conf-noct"
mkwrap usr/bin/dtach dtach-noct "$SB/real-dtach" "$SB/lib/pve-console-replay" "$SB/conf-noct"
out=$(tty_run "$SB/dtach-noct" -A /var/run/dtach/vzctlconsole200 -r winch -z lxc-console -n 200)
expect_not "REPLAY_CT=no disables the replay" "$out" "--- replay"
sleep 1
if pgrep -f "$SB" >/dev/null; then fail "no background jobs left behind" "$(pgrep -af "$SB")"; else ok "no background jobs left behind"; fi

echo "$passes passed, $fails failed"
[ "$fails" = 0 ]
