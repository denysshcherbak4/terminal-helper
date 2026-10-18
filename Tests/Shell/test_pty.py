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
    def __init__(self, home, integrated=True, custom_enter=False, enter_macro=False, initialize_completion=True):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home),
                   'TERM': 'xterm-256color', 'LC_ALL': 'en_US.UTF-8'}
            os.execve('/bin/zsh', ['zsh', '-f'], env)
        self.read()
        completion_setup = "autoload -Uz compinit; compinit -D; " if initialize_completion else ""
        self.send("PROMPT='TH> '; RPROMPT=''; setopt no_beep; bindkey -e; "
                  + completion_setup +
                  "function dump_buffer() { print -r --; print -r -- DUMP:${(qqq)BUFFER}:$CURSOR; }; "
                  "zle -N dump_buffer; bindkey '^]' dump_buffer; print -r -- TH'_'READY\n")
        self.wait_for('TH_READY\r\n')
        if custom_enter:
            self.send("function custom_enter() { print CUSTOM_ENTER_CALLED; zle .accept-line; }; zle -N custom_enter; bindkey '^M' custom_enter\n")
            self.read()
        if enter_macro:
            self.send("bindkey -s '^M' 'MACRO_LITERAL'\n")
            self.read()
        if integrated:
            self.send('source ' + str(ROOT / 'Integration/terminal-helper.zsh').replace(' ', '\\ ') + "; print -r -- TH'_'SOURCED\n")
            self.wait_for('TH_SOURCED\r\n')

    def wait_for(self, marker, timeout=15):
        data = ''
        deadline = time.monotonic() + timeout
        while marker not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError('Interactive shell did not reach readiness marker')
            data += self.read(min(0.1, remaining))
        self.read(0.03)
        return data

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
        try:
            os.kill(self.pid, signal.SIGHUP)
            deadline = time.monotonic() + 0.5
            while time.monotonic() < deadline:
                if os.waitpid(self.pid, os.WNOHANG)[0]:
                    break
                time.sleep(0.01)
            else:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
        except (ProcessLookupError, ChildProcessError):
            pass
        finally:
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

    def test_leading_dash_fuzzy_requires_explicit_path(self):
        candidate = self.home / '-rf'
        candidate.write_text('KEEP')
        important = self.home / 'important'
        important.write_text('KEEP')
        text = 'cat xrf important'
        self.shell.send(text + '\x1b[D' * len(' important') + '\t')
        self.shell.read(0.8)
        self.assertIn('DUMP:"cat xrf important":7', self.shell.buffer())
        self.shell.send('\x15')
        self.complete('cat ./xrf')
        self.shell.send('\r')
        self.assertIn('./-rf', self.shell.buffer())
        self.assertEqual(candidate.read_text(), 'KEEP')
        self.assertEqual(important.read_text(), 'KEEP')

    def test_edit_after_unique_completion_keeps_ordinary_enter(self):
        self.complete('cat note')
        self.shell.send('\x15print EDITED_ENTER_WORKS\r')
        out = self.shell.read()
        self.assertIn('EDITED_ENTER_WORKS\r\n', out)
        self.assertNotIn('DUMP:', out)

    def test_custom_native_menu_bindings_are_restored(self):
        self.shell.send("zmodload zsh/complist; function custom_menu_key() { zle -M CUSTOM_MENU; }; zle -N custom_menu_key; bindkey -M menuselect '^M' custom_menu_key\n")
        self.shell.read()
        (self.home / 'ChoiceOne').mkdir()
        (self.home / 'ChoiceTwo').mkdir()
        for ending in ('\r', '\x1b'):
            self.complete('cd Cho')
            self.shell.send(ending)
            self.shell.read(0.5)
            self.shell.send('\x15bindkey -M menuselect "^M"\r')
            out = self.shell.read()
            self.assertIn('custom_menu_key', out)
            self.assertNotIn('_th_menu_accept', out)
        self.complete('cd Cho')
        self.state(False)
        self.shell.send('\r')
        self.shell.read()
        self.shell.send('\x15bindkey -M menuselect "^M"\r')
        self.assertIn('custom_menu_key', self.shell.read())

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

    def test_bracketed_paste_multiline_is_inert_and_unchanged(self):
        sentinel = self.home / 'PASTE_MUST_NOT_EXECUTE'
        text = 'touch ' + str(sentinel) + '\nprint PASTED_SECOND'
        self.shell.send('\x1b[200~' + text + '\x1b[201~\t')
        self.shell.read(0.8)
        out = self.shell.buffer().replace('\r\n', '\n')
        expected = 'DUMP:"' + text + '":' + str(len(text))
        self.assertIn(expected, out)
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


    def test_terminal_control_filename_is_displayed_safely(self):
        out = self.complete('cat evi')
        self.shell.send('\r')
        out += self.shell.buffer()
        self.assertIn('evil', out)
        self.assertNotIn('\x1b[31m', out)

    def test_key_macro_refuses_integration_without_changing_binding(self):
        self.shell.close()
        self.shell = Shell(self.home, enter_macro=True)
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('MACRO_LITERAL', out)

    def test_existing_tilde_file_not_replaced_by_similar_directory(self):
        (self.home / 'data').touch()
        (self.home / 'date').mkdir()
        self.complete('cd ~/data')
        self.assertIn('cd ~/data', self.shell.buffer())
        self.assertNotIn('~/date', self.shell.buffer())

    def test_custom_enter_guarded_and_idle_delegates(self):
        self.shell.close()
        self.shell = Shell(self.home, custom_enter=True)
        self.shell.send('cd ' + str(self.home) + '\r')
        self.shell.read()
        self.complete('cat note')
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('notebook.ipynb', out)
        self.assertNotIn('CUSTOM_ENTER_CALLED', out)
        self.shell.send('\x15print IDLE_ENTER_WORKS\r')
        out = self.shell.read()
        self.assertIn('CUSTOM_ENTER_CALLED', out)
        self.assertIn('IDLE_ENTER_WORKS\r\n', out)

    def test_unrelated_keybinding_preserved(self):
        self.shell.send("function custom_key() { BUFFER='CUSTOM_KEY_PRESERVED'; CURSOR=${#BUFFER}; }; zle -N custom_key; bindkey '^K' custom_key\n")
        self.shell.read()
        self.shell.send('\x0b')
        self.assertIn('CUSTOM_KEY_PRESERVED', self.shell.buffer())

    def test_quoted_path_and_hostile_filename_are_literal(self):
        sentinel = self.home / 'SHOULD_NOT_EXIST'
        (self.home / 'attack$(touch SHOULD_NOT_EXIST).csv').touch()
        self.complete('cat atta')
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('attack', out)
        self.assertIn('SHOULD_NOT_EXIST', out)
        self.assertFalse(sentinel.exists())
        self.shell.send('\x15')
        self.complete('cat "spa')
        self.shell.send('\r')
        self.assertIn('space', self.shell.buffer())

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


def benchmark(repetitions=30, initialize_completion=True):
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
        shell = Shell(home, initialize_completion=initialize_completion)
        shell.send('cd ' + str(home) + '\n')
        shell.read()
        results = []
        try:
            for iteration in range(repetitions):
                if iteration and not initialize_completion:
                    shell.close()
                    shell = Shell(home, initialize_completion=False)
                    shell.send('cd ' + str(home) + '\n')
                    shell.read()
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
        if not initialize_completion:
            ordered = sorted(results)
            return {'method': 'Fresh PTY shell without compinit: Tab through initialization to visible filename insertion; OS caches not flushed',
                    'fixture_entries': 256, 'repetitions': repetitions,
                    'first_observation_ms': results[0],
                    'fresh_shell_p95_ms': ordered[min(len(ordered)-1, int(len(ordered)*.95))],
                    'all_ms': results}
        ordered = sorted(results[1:])
        return {'method': 'PTY Tab to visible unique filename insertion',
                'fixture_entries': 256, 'repetitions': repetitions,
                'first_ms': results[0], 'warm_p95_ms': ordered[min(len(ordered)-1, int(len(ordered)*.95))],
                'all_ms': results}


if __name__ == '__main__':
    import sys
    if '--benchmark-uninitialized' in sys.argv:
        print(json.dumps(benchmark(initialize_completion=False), indent=2))
    elif '--benchmark' in sys.argv:
        print(json.dumps(benchmark(), indent=2))
    else:
        unittest.main(verbosity=2)

