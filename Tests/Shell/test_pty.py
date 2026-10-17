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
                  "zle -N dump_buffer; bindkey '^X' dump_buffer\n")
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
        self.send('\x18')
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
        self.assertIn('/denys', self.shell.buffer())

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
        self.shell.send("BUFFER=$'echo first\\necho second'; CURSOR=${#BUFFER}\n")
        self.shell.read()
        # Pasted text is not passed through eval or a command reconstruction layer.
        self.complete("echo 'unterminated")
        self.assertIn('unterminated', self.shell.buffer())

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
