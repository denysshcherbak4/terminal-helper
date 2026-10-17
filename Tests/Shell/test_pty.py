#!/usr/bin/env python3
"""Actual interactive ZLE checks; no dependency beyond Python 3 and system zsh."""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Shell:
    def __init__(self, home, integrated=True):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home),
                   'TERM': 'xterm-256color', 'LC_ALL': 'en_US.UTF-8'}
            os.execve('/bin/zsh', ['zsh', '-f'], env)
        self.read()
        self.send("PROMPT='TH> '; RPROMPT=''; setopt no_beep; bindkey -e; "
                  "autoload -Uz compinit; compinit -D; "
                  "function dump_buffer() { print -r --; print -r -- DUMP:${(qqq)BUFFER}:$CURSOR; }; "
                  "zle -N dump_buffer; bindkey '^]' dump_buffer\n")
        self.read()
        if integrated:
            self.send('source ' + str(ROOT / 'Integration/terminal-helper.zsh').replace(' ', '\\ ') + '\n')
            self.read()

    def send(self, data):
        os.write(self.fd, data.encode())

    def read(self, timeout=0.25):
        data = b''
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            ready, _, _ = select.select([self.fd], [], [], max(0, until-time.monotonic()))
            if ready:
                try:
                    data += os.read(self.fd, 65536)
                except OSError:
                    break
        return data.decode(errors='replace')

    def buffer(self):
        self.send('\x1d')
        return self.read()

    def close(self):
        os.kill(self.pid, signal.SIGHUP)
        os.waitpid(self.pid, 0)
        os.close(self.fd)


class CompletionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.base = self.home / 'Library/Application Support/Terminal Helper'
        self.base.mkdir(parents=True, mode=0o700)
        self.state(True)
        (self.home / 'Documents').mkdir()
        (self.home / 'denys').mkdir()
        (self.home / 'space name.csv').touch()
        (self.home / 'дані.parquet').touch()
        (self.home / 'notebook.ipynb').touch()
        (self.home / 'valid').mkdir()
        (self.home / 'valids').mkdir()
        (self.home / 'link').symlink_to(self.home / 'Documents')
        (self.home / 'evil\x1b[31m.csv').touch()
        self.shell = Shell(self.home)
        self.shell.send('cd ' + str(self.home) + '\n')
        self.shell.read()

    def tearDown(self):
        self.shell.close()
        self.temp.cleanup()

    def state(self, enabled):
        target = self.base / 'state'
        target.write_text('terminal-helper-v1:' + ('on' if enabled else 'off') + '\n')
        target.chmod(0o600)

    def complete(self, text):
        self.shell.send(text + '\t')
        return self.shell.read(0.8)

    def test_directory_prefix_and_accept_does_not_execute(self):
        self.complete('cd ~/Doc')
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('Documents', out)
        self.assertIn('DUMP:', out)
        self.assertIn('cd ', out)

    def test_typo(self):
        self.complete('cd ' + str(self.home) + '/dents')
        self.shell.send('\r')
        self.assertIn(str(self.home) + '/denys', self.shell.buffer())

    def test_escape_restores_buffer(self):
        self.complete('cd ~/Doc')
        self.shell.send('\x1b')
        time.sleep(0.15)
        self.assertIn('cd ~/Doc', self.shell.buffer())

    def test_off_does_not_complete(self):
        self.state(False)
        self.complete('cd ~/Doc')
        self.assertIn('cd ~/Doc', self.shell.buffer())

    def test_pending_disable(self):
        self.complete('cd ~/Doc')
        self.state(False)
        self.shell.send('\r')
        self.assertIn('cd ~/Doc', self.shell.buffer())

    def test_reenable(self):
        self.state(False)
        self.complete('cd ~/Doc')
        self.state(True)
        self.shell.send('\t\r')
        self.assertIn('Documents', self.shell.buffer())

    def test_unsupported_command_is_not_evaluated(self):
        sentinel = self.home / 'EXECUTED'
        text = 'echo $(touch ' + str(sentinel) + ')'
        self.complete(text)
        self.assertIn('$(touch ', self.shell.buffer())
        self.assertFalse(sentinel.exists())

    def test_multiline_unsupported(self):
        self.shell.send("function multiline_buffer() { BUFFER=$'echo first\\necho second'; CURSOR=${#BUFFER}; }; zle -N multiline_buffer; bindkey '^Y' multiline_buffer\n")
        self.shell.read()
        self.shell.send('\x19\t')
        self.shell.read()
        out = self.shell.buffer()
        self.assertIn('echo first', out)
        self.assertIn('echo second', out)
        self.assertNotIn('\r\nsecond\r\n', out)

    def test_file_spaces_unicode_symlink(self):
        for text, expected in [('cat spa', 'space'), ('cat дан', 'дані'), ('cd lin', 'link')]:
            self.shell.send('\x15')
            self.complete(text)
            self.shell.send('\r')
            self.assertIn(expected, self.shell.buffer())

    def test_valid_path_not_fuzzy_replaced(self):
        self.complete('cd valid')
        self.shell.send('\x1b')
        time.sleep(0.15)
        self.assertIn('cd valid', self.shell.buffer())

    def test_missing_and_malformed_state(self):
        for value in [None, 'terminal-helper-v1:on\nextra', 'terminal-helper-v1:on']:
            target = self.base / 'state'
            if value is None:
                target.unlink(missing_ok=True)
            else:
                target.write_text(value)
                target.chmod(0o600)
            self.shell.send('\x15')
            self.complete('cd ~/Doc')
            self.assertIn('cd ~/Doc', self.shell.buffer())

    def test_normal_enter_unchanged(self):
        self.shell.send('print NORMAL_ENTER\r')
        self.assertIn('NORMAL_ENTER', self.shell.read())


    def test_unrelated_keybinding_preserved(self):
        self.shell.send("function custom_key() { BUFFER='CUSTOM_KEY_PRESERVED'; CURSOR=${#BUFFER}; }; zle -N custom_key; bindkey '^K' custom_key\n")
        self.shell.read()
        self.shell.send('\x0b')
        self.assertIn('CUSTOM_KEY_PRESERVED', self.shell.buffer())

    def test_quoted_path_and_hostile_filename_are_literal(self):
        sentinel = self.home / 'SHOULD_NOT_EXIST'
        (self.home / '$(touch SHOULD_NOT_EXIST).csv').touch()
        self.complete('cat "spa')
        self.shell.send('\r')
        self.assertIn('space', self.shell.buffer())
        self.assertFalse(sentinel.exists())

    def test_ambiguous_cycle_escape_restores_original_cursor(self):
        (self.home / 'ChoiceOne').mkdir()
        (self.home / 'ChoiceTwo').mkdir()
        self.complete('cd Cho')
        self.shell.send('\t\x1b')
        time.sleep(0.5)
        out = self.shell.buffer()
        self.assertIn('DUMP:"cd Cho":6', out)

    def test_arrow_navigation_and_enter_only_edits(self):
        (self.home / 'ChoiceOne').mkdir()
        (self.home / 'ChoiceTwo').mkdir()
        self.complete('cd Cho')
        self.shell.send('\x1b[B\r')
        self.shell.read()
        out = self.shell.buffer()
        self.assertIn('DUMP:', out)
        self.assertIn('Choice', out)
        self.assertIn('cd ', out)

    def test_executable_completion(self):
        self.complete('pytho')
        self.shell.send('\r')
        self.assertIn('python', self.shell.buffer())

    def test_git_command_completion(self):
        self.complete('git che')
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('git ', out)
        self.assertTrue(any(word in out for word in ('checkout', 'cherry', 'check-')), out)

    def test_case_sensitive_fixture(self):
        upper, lower = self.home / 'CaseUnique.csv', self.home / 'caseunique.csv'
        upper.touch()
        lower.touch()
        if os.path.samefile(upper, lower):
            self.skipTest('Runner fixture filesystem is case-insensitive')
        self.complete('cat CaseU')
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('CaseUnique.csv', out)
        self.assertNotIn('caseunique.csv', out)

    def test_no_match_keeps_normal_enter(self):
        self.complete('print MISSING_COMPLETION_xyz123')
        self.shell.send('\r')
        out = self.shell.read()
        self.assertIn('MISSING_COMPLETION_xyz123\r\n', out)

    def test_cursor_middle_preserves_suffix(self):
        self.shell.send('cat not tail' + '\x1b[D' * 5 + '\t')
        self.shell.read(0.8)
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('notebook.ipynb', out)
        self.assertIn(' tail', out)

    def test_multiple_shells_observe_same_state(self):
        second = Shell(self.home)
        try:
            self.state(False)
            for shell in (self.shell, second):
                shell.send('cd ~/Doc\t')
                shell.read()
                self.assertIn('cd ~/Doc', shell.buffer())
        finally:
            second.close()

    def test_state_permissions_and_symlink_rejected(self):
        target = self.base / 'state'
        target.chmod(0o644)
        self.complete('cd ~/Doc')
        self.assertIn('cd ~/Doc', self.shell.buffer())
        self.shell.send('\x15')
        target.unlink()
        elsewhere = self.home / 'elsewhere'
        elsewhere.write_text('terminal-helper-v1:on\n')
        elsewhere.chmod(0o600)
        target.symlink_to(elsewhere)
        self.complete('cd ~/Doc')
        self.assertIn('cd ~/Doc', self.shell.buffer())


def benchmark(repetitions=30):
    """Measure actual useful insertion in a PTY, excluding fixture/shell setup."""
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        base = home / 'Library/Application Support/Terminal Helper'
        base.mkdir(parents=True, mode=0o700)
        state = base / 'state'
        state.write_text('terminal-helper-v1:on\n')
        state.chmod(0o600)
        for index in range(255):
            (home / ('dataset_%03d.csv' % index)).touch()
        (home / 'perf-target-final.csv').touch()
        shell = Shell(home)
        shell.send('cd ' + str(home) + '\n')
        shell.read()
        results = []
        try:
            for _ in range(repetitions):
                shell.send('\x15cat perf-target-fina')
                shell.read(0.03)
                start = time.perf_counter()
                shell.send('\t')
                data = b''
                deadline = start + 5
                while b'l.csv' not in data:
                    remaining = deadline - time.perf_counter()
                    if remaining <= 0:
                        raise AssertionError('No useful completion appeared within five seconds')
                    ready, _, _ = select.select([shell.fd], [], [], remaining)
                    if ready:
                        data += os.read(shell.fd, 65536)
                results.append((time.perf_counter() - start) * 1000)
                shell.send('\r\x15')
                shell.read(0.03)
        finally:
            shell.close()
        ordered = sorted(results[1:])
        return {'method': 'PTY Tab to visible unique filename insertion',
                'fixture_entries': 256, 'repetitions': repetitions,
                'first_ms': results[0], 'warm_p95_ms': ordered[min(len(ordered)-1, int(len(ordered)*.95))],
                'all_ms': results}


if __name__ == '__main__':
    import sys
    if '--benchmark' in sys.argv:
        print(json.dumps(benchmark(), indent=2))
    else:
        unittest.main(verbosity=2)

