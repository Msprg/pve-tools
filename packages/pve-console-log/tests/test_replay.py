# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for pve-console-replay. Synthetic logs only.

Run: python3 -m unittest discover -s packages/pve-console-log/tests
Each test runs the renderer as a subprocess in plain mode, and in rendered mode
too when python3-pyte is importable (skipped otherwise).
"""
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER = os.path.join(HERE, '..', 'root', 'usr', 'lib', 'pve-console-log', 'pve-console-replay')
E = '\x1b'

try:
    import pyte  # noqa: F401
    HAVE_PYTE = True
except ImportError:
    HAVE_PYTE = False

SGR = re.compile(r'\x1b\[[0-9;:]*m')
ANY_ESC = re.compile(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)?|.)', re.S)
BAD_CONTROLS = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1a\x1c-\x1f\x7f-\x9f]')


def run(log_bytes, *args, plain=False):
    with tempfile.NamedTemporaryFile(suffix='.log', delete=False) as f:
        f.write(log_bytes)
        path = f.name
    try:
        cmd = [sys.executable, '-I', RENDER] + (['--plain'] if plain else []) + [path] + list(args)
        p = subprocess.run(cmd, capture_output=True, timeout=30)
        return p.returncode, p.stdout.decode('utf-8'), p.stderr.decode()
    finally:
        os.unlink(path)


def visible(out):
    """Output as plain lines, colours removed, banners kept."""
    return [l for l in SGR.sub('', out).replace('\r', '').split('\n')]


def body(out):
    lines = visible(out)
    assert lines[0].startswith('--- replay: last '), lines[0]
    end = lines.index('--- end of replay ---')
    return lines[1:end]


class Base(unittest.TestCase):
    modes = ['plain'] + (['rendered'] if HAVE_PYTE else [])

    def each_mode(self, log, *args):
        """Run the renderer in every available mode; returns [(mode, output)]."""
        results = []
        for mode in self.modes:
            rc, out, err = run(log, *args, plain=(mode == 'plain'))
            self.assertEqual(rc, 0, f'{mode}: {err}')
            self.assertSafe(out, mode)
            results.append((mode, out))
        return results

    def assertSafe(self, out, mode=''):
        """Nothing but text, SGR colours and CR LF may reach the live terminal."""
        bad = [m.group(0) for m in ANY_ESC.finditer(out) if not SGR.fullmatch(m.group(0))]
        self.assertEqual(bad, [], f'{mode}: non-SGR escape sequences in replay')
        self.assertEqual(BAD_CONTROLS.findall(out), [], f'{mode}: control characters in replay')
        self.assertEqual(re.findall(r'(?<!\r)\n', out), [], f'{mode}: bare LF (needs CR LF on a raw tty)')
        self.assertTrue(out.endswith('--- end of replay ---\r\n'), mode)


class TestBasics(Base):
    def test_boot_log_kept_with_colours(self):
        log = ('[    0.000000] Linux version 6.8.0 (build@host)\r\n'
               f'[  {E}[0;32mOK{E}[0m  ] Reached target {E}[0;1;39mmulti-user.target{E}[0m\r\n'
               'guest login: ').encode()
        for mode, out in self.each_mode(log):
            self.assertIn('Linux version 6.8.0', out)
            self.assertIn(f'{E}[', out, 'colour codes are kept')
            self.assertIn('guest login:', '\n'.join(body(out)))

    def test_line_limit_and_banner_count(self):
        log = ''.join(f'line {i}\r\n' for i in range(5000)).encode()
        for mode, out in self.each_mode(log, '100'):
            b = body(out)
            self.assertEqual(len(b), 100)
            self.assertEqual(b[-1], 'line 4999')
            self.assertTrue(visible(out)[0].startswith('--- replay: last 100 lines'))

    def test_lines_argument_is_clamped(self):
        rc, out, _ = run(b'x\r\n', '99999999999', plain=True)
        self.assertEqual(rc, 0)
        self.assertSafe(out)

    def test_bad_arguments_exit_nonzero(self):
        p = subprocess.run([sys.executable, '-I', RENDER], capture_output=True)
        self.assertNotEqual(p.returncode, 0)
        p = subprocess.run([sys.executable, '-I', RENDER, '/nonexistent/log'], capture_output=True)
        self.assertNotEqual(p.returncode, 0)

    def test_tail_cut_mid_utf8_and_mid_line(self):
        # > 512 KB so even plain mode cuts; multibyte chars everywhere
        log = ('žluťoučký kůň ⏺ │ ' * 40 + '\r\n').encode() * 1500 + 'last line ✓\r\n'.encode()
        for mode, out in self.each_mode(log):
            self.assertIn('last line ✓', out)
            self.assertNotIn('�', '\n'.join(body(out)[1:]), 'only the first line may be cut')


class TestTerminalControl(Base):
    def test_queries_and_modes_never_reach_the_terminal(self):
        queries = [f'{E}[6n', f'{E}[c', f'{E}[>0q', f'{E}[?2026$p', f'{E}[?u', f'{E}[<u', f'{E}[=1;1u',
                   f'{E}]11;?{E}\\', f'{E}]10;?\x07', f'{E}P+q544e{E}\\', f'{E}_Gf=100;AAAA{E}\\',
                   f'{E}[?1000h', f'{E}[?1006h', f'{E}[?2004h', f'{E}[?1h{E}=', f'{E}[22;0;0t', f'{E}c', f'{E}#8']
        log = ('A' + ''.join(queries) + 'Z\r\nafter\r\n').encode()
        for mode, out in self.each_mode(log):
            b = body(out)
            self.assertIn('AZ', b, 'sequences must vanish without leaving printable debris')
            self.assertIn('after', b)

    def test_scroll_region_and_clear_do_not_leak(self):
        # nano under TERM=linux: no alternate screen, sets a scroll region and clears
        log = (f'root@ct:~# ls\r\nfile-a\r\nroot@ct:~# nano test\r\n'
               f'{E})0{E}[1;24r{E}[m{E}[H{E}[J{E}[22;35H[ New File ]{E}[1;1H  GNU nano 7.2\r\n'
               f'{E}[24;1H{E}[J{E}[r{E}[24;1Hroot@ct:~# echo done\r\ndone\r\n').encode()
        for mode, out in self.each_mode(log):
            joined = '\n'.join(body(out))
            self.assertIn('file-a', joined, 'history before the TUI survives')
            self.assertIn('done', joined)

    def test_dec_line_drawing_becomes_unicode(self):
        log = (f'{E})0\x0elqqk\x0f box \x0emqqj\x0f\r\n'          # TERM=linux: G1 + SO/SI
               f'{E}(0lqqk{E}(B xterm {E}(0x{E}[1mq{E}[0mx{E}(B\r\n').encode()  # xterm: G0, SGR inside
        for mode, out in self.each_mode(log):
            b = body(out)
            self.assertIn('┌──┐ box └──┘', b)
            self.assertIn('┌──┐ xterm │─│', b)


class TestFullScreenApps(Base):
    def test_finished_alt_screen_session_becomes_marker(self):
        log = (f'$ vim /etc/hosts\r\n{E}[?1049h{E}[H{E}[2J127.0.0.1 localhost\r\n~\r\n~\r\n'
               f'{E}[?1049l$ echo after-vim\r\nafter-vim\r\n').encode()
        for mode, out in self.each_mode(log):
            joined = '\n'.join(body(out))
            self.assertIn('[full-screen app output omitted]', joined)
            self.assertNotIn('127.0.0.1 localhost', joined, 'editor contents are not replayed')
            self.assertIn('after-vim', joined)

    def test_tail_starting_inside_alt_screen(self):
        # the cut lands inside a full-screen session: its end must not leak the rest
        log = (f'secret-editor-content\r\n{E}[?1049l$ ls\r\nfile-b\r\n').encode()
        for mode, out in self.each_mode(log):
            joined = '\n'.join(body(out))
            self.assertNotIn('secret-editor-content', joined)
            self.assertIn('file-b', joined)

    def test_still_running_alt_screen(self):
        log = (f'$ htop\r\n{E}[?1049h{E}[?1000h{E}[H{E}[2J  CPU[{E}[32m||||{E}[0m 12.0%]\r\n'
               f'  PID USER COMMAND\r\n    1 root systemd').encode()
        for mode, out in self.each_mode(log):
            joined = '\n'.join(body(out))
            self.assertIn('still running', joined)
            if mode == 'rendered':
                self.assertIn('1 root systemd', joined, 'rendered mode shows the last frame')


@unittest.skipUnless(HAVE_PYTE, 'python3-pyte not installed')
class TestRendering(Base):
    modes = ['rendered']

    def test_redraws_collapse_to_final_frame(self):
        # Claude Code style: synchronized output + cursor-up/erase-line redraws in the main buffer
        log = ('$ claude\r\n'
               + ''.join(f'{E}[?2026h\r{E}[2K⏺ Thinking… ({i}s){E}[?2026l' for i in range(1, 6))
               + f'\r{E}[2K⏺ The disk is 87% full.\r\n'
               + 'Progress: 10%\rProgress: 55%\rProgress: 100%\r\n').encode()
        for mode, out in self.each_mode(log):
            b = body(out)
            self.assertIn('⏺ The disk is 87% full.', b)
            self.assertIn('Progress: 100%', b)
            self.assertNotIn('Thinking', '\n'.join(b))

    def test_clear_screen_keeps_history(self):
        log = (f'before-clear\r\n{E}[H{E}[2Jafter-clear\r\n').encode()
        for mode, out in self.each_mode(log):
            b = body(out)
            self.assertLess(b.index('before-clear'), b.index('after-clear'))


if __name__ == '__main__':
    unittest.main()
