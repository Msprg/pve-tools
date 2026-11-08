# pve-console-log

Persistent console scrollback for Proxmox VE guests. The PVE web console (xterm.js,
noVNC, SPICE) shows a guest's console only from the moment you open it: boot
messages, kernel output, a shutdown that hung, a link that flapped five minutes ago
are gone. pve-console-log keeps a log of every enabled guest's console from the
moment it starts, whether or not anyone is watching, and replays the tail of that
log when you open the console.

## How it works

- **VMs**: the guest's serial port (`serial0: socket`) gets QEMU's own `logfile=`
  option through a `-set` override in the VM's `args:`. QEMU appends everything the
  guest writes to `/var/log/pve-console-<vmid>.serial0.log`, from the first kernel
  line on, across guest reboots and VM restarts. No daemon, no hookscript, and the
  socket the GUI talks to is unchanged.
- **CTs**: the container gets `cmode: console` (otherwise the GUI attaches to a getty
  on tty1, which never shows boot output) and the raw key `lxc.console.logfile:`, so
  liblxc writes the container's `/dev/console` to `/var/log/pve-console-<ctid>.console.log`.
- **Replay**: the package diverts `/usr/sbin/qm` and `/usr/bin/dtach` (`dpkg-divert`,
  the real binaries move to `*.real` and package upgrades land there) and puts small
  wrappers in their place. The GUI's VM console runs `qm terminal`, every CT console
  runs `dtach -A /var/run/dtach/vzctlconsole<ctid> … lxc-console`; for exactly those
  calls the wrapper first prints the last 1000 lines of the log. Every other call is a
  plain `exec` of the real binary.

## Install

From the apt repository (see the [top-level README](../../README.md#install)):

```sh
apt install pve-console-log
```

`python3-pyte` (recommended, installed by default) makes the replay render through a
terminal emulator; without it a plain filter is used.

## Use

```sh
pve-console-log enable 100        # VM 100 (serial0) or CT 100 - add -n for a dry run
qm reboot 100                     # or stop+start; pct reboot for a CT
pve-console-log status            # what is set up on this node
pve-console-log show 100 | less -R
pve-console-log disable 100
```

Then open **Console → xterm.js** on the guest: the replay appears above the live console.

Only `root@pam` can set a VM's `args:`. Run the command on the node the guest lives on.

### The guest must use its serial console

A VM only logs what it writes to the serial port. Linux guests need the serial console
on the kernel command line, e.g. in `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200"
```

(`update-grub`, reboot). List `ttyS0` last: it becomes `/dev/console`, so systemd's
status lines - including "A stop job is running…" during a stuck shutdown - go there
too. Drop `quiet` if you want the full kernel log. Many cloud images already do this.

### Recommended guest tweaks

In `/usr/share/doc/pve-console-log/examples/guest/`:

- `getty-xterm.conf` - systemd drop-in that runs the console getty with
  `TERM=xterm-256color`. The GUI console *is* an xterm; with the default `TERM=linux` /
  `vt220` there is no alternate screen, so nano/vim/less draw over the history and
  F-keys, Home and End misbehave. Install as
  `/etc/systemd/system/console-getty.service.d/xterm.conf` (CT) or
  `/etc/systemd/system/serial-getty@ttyS0.service.d/xterm.conf` (VM).
- `console-size.sh` - `/etc/profile.d` snippet that asks the terminal for its size at
  login. A serial line carries no window size and a CT console stays at 80x24, so
  full-screen apps would otherwise draw for 80x24. Re-run `console_size` after resizing
  the browser window.

## Configuration

`/etc/default/pve-console-log` (read, never sourced, by the wrappers on each console open):

| Key | Default | |
|---|---|---|
| `REPLAY_LINES` | `1000` | lines replayed (PVE's xterm.js keeps 1000 lines of scrollback) |
| `REPLAY_VM` | `yes` | `no`: keep logging VMs, stop replaying |
| `REPLAY_CT` | `yes` | same for CTs |

Logs are rotated weekly (or at 20 MB) by `/etc/logrotate.d/pve-console-log`, 8 kept.
Both writers keep the file open in append mode, so `copytruncate` is safe.

## Why the replay is safe to print into your terminal

A console log is a raw recording of terminal output: cursor movement, screen clears,
scroll regions, alternate-screen switches, mouse and keypad modes, and terminal
*queries* (cursor position, colours, mode support) that the terminal answers as if
the answer had been typed. Replayed raw, that history would wipe itself, leak modes
into the live session, and make xterm.js type into the guest. The renderer
(`/usr/lib/pve-console-log/pve-console-replay`) therefore only ever emits printable
text, CR LF and SGR colour codes. With python3-pyte it first renders the tail through
a terminal emulator, so redraws (progress bars, Claude Code's redrawn status lines,
TUIs on the main screen) collapse to what was actually visible and line drawing shows
as box characters; full-screen sessions (nano, vim, htop on the alternate screen) are
replaced by one marker line, and one still running at the end shows its last frame.
The replay is therefore *safer* than the live stream: a guest can already send
queries live, but nothing in the replay can act on your terminal.

The wrappers run as root on every `qm` / `dtach` call, so they are kept minimal: no
`set -e`, the config is parsed rather than sourced, the replay is skipped unless every
check passes, it is time-limited (3 s), and the final `exec` of the real binary is
unconditional.

## Compatibility

| | |
|---|---|
| Tested | PVE 8.4 (Debian 12, QEMU 9.2, lxc 6.0), on real VMs and CTs; package install/upgrade/remove/purge on Debian 13 |
| Checked against source | PVE 9: `qm terminal` still uses socat, the GUI still runs `/usr/sbin/qm`, CT consoles still go through `dtach`, `lxc.console.logfile` is still accepted; Debian 13 ships the same pyte 0.8.0 |
| Not tested | QEMU 10 with the `-set` logging options, SeaBIOS guests, `vga: serial0`, `serial1`-`serial3`, clusters |
| Not applicable | Windows guests (no serial console by default) |

Reports from other setups are welcome.

## Clusters and migration

The package is per node: install it on every node. The logging settings travel with
the guest config, and the log path needs no directory, so a migrated guest still
starts on a node without the package - it keeps logging there, but there is no replay
or rotation on that node, and the history is split between the nodes' `/var/log`.

## Removal

`apt remove pve-console-log` removes the wrappers and moves the real `qm` and `dtach`
back. Guests you enabled keep logging (QEMU and liblxc write the file themselves) until
you run `pve-console-log disable <id>` - do that before removing; `apt purge` lists
the guest configs that still point at a log.

## Limitations

- CT replay is printed about half a second after attaching (dtach clears the screen on
  attach); a CT printing heavily at that moment interleaves with the replay.
- A full-screen app still running in a VM is not redrawn on attach (the serial line has
  no resize signal); the replay shows its last frame - press Ctrl-L.
- With python3-pyte the rendered window is byte-limited (~192 KB for 1000 lines), so
  logs dominated by redraws replay fewer than 1000 lines; bright colours show as normal.
- The replay shows an editor's last screen when it was still open at the end of the log
  - file contents shown on the console reappear on the next open (they are in the log
  anyway; logs are root-only).

## Upstream

The logging half would be a few lines in qemu-server (an option on `serialN: socket`),
which would make it work without a mod. If you care, that is a proposal for the
pve-devel mailing list.
