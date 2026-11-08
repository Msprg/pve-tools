# pve-console-log: /etc/profile.d/console-size.sh
# A serial line carries no window size, and an LXC console under the PVE GUI
# stays at 24x80, so full-screen apps would draw for 80x24 inside a bigger
# xterm.js. On login on such a console, ask the terminal for its size once.
# After resizing the browser window, run `console_size` again.
console_size() {
    [ -n "$BASH_VERSION" ] && [ -t 0 ] && [ -t 1 ] || return 0
    local _ rows cols
    # save cursor, jump to the far bottom-right (clamped to the real size), report position, restore cursor
    printf '\0337\033[999;999H\033[6n\0338'
    IFS='[;' read -r -s -d R -t 1 _ rows cols || return 0
    [ "${rows:-0}" -gt 0 ] 2>/dev/null && [ "${cols:-0}" -gt 0 ] 2>/dev/null && stty rows "$rows" cols "$cols"
}
case "$(tty 2>/dev/null)" in
    /dev/ttyS*|/dev/console|/dev/hvc*) console_size ;;
esac
