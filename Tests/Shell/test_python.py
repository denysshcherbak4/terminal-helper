#!/usr/bin/env python3
"""Explicit Python context: real ZLE, controlled fixture executables that must never run."""
import json
import os
from pathlib import Path
import re
import select
import shlex
import statistics
import sys
import tempfile
import time
import unittest
from test_pty import Shell, ROOT

CFG = 'home = /synthetic/python\ninclude-system-site-packages = false\nversion = 3.12.0\n'
CLEAR = ('SSH_CONNECTION SSH_CLIENT SSH_TTY REMOTE_CONTAINERS DEVCONTAINER CODESPACES '
         'VSCODE_REMOTE_NAME CONTAINER container KUBERNETES_SERVICE_HOST WSL_DISTRO_NAME '
         'PIP_TARGET PIP_PREFIX PIP_ROOT PIP_USER PIP_CONFIG_FILE PIP_PYTHON '
         'PIP_REQUIRE_VIRTUALENV PYTHONHOME PYTHONPATH CONDA_PREFIX CONDA_DEFAULT_ENV VIRTUAL_ENV')
SHORTCUT = '\x18\x10'


class PythonFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.project = self.home / 'project'
        self.project.mkdir()
        self.base = self.home / 'Library/Application Support/Terminal Helper'
        self.base.mkdir(parents=True, mode=0o700)
        self.state(True)
        self.global_bin = self.home / 'global-bin'
        self.global_bin.mkdir()
        self.sentinel = self.home / 'MUST_NOT_EXECUTE'
        for name in ('pip', 'pip3', 'python', 'python3'):
            self.executable(self.global_bin / name)
        self.environment(self.project)
        self.shell = Shell(self.home, initialize_completion=False)
        setup = ('unset ' + CLEAR + '; PATH=' + shlex.quote(str(self.global_bin)) + ':$PATH; '
                 "print -r -- PY_NATIVE:$_TH_PY_SHORTCUT_STATUS; bindkey -M emacs '^X'; bindkey -M emacs '^X^P'; "
                 "bindkey -M emacs '^X' undefined-key; bindkey -M emacs '^X^P' undefined-key; "
                 "bindkey -M viins '^X' undefined-key; bindkey -M viins '^X^P' undefined-key; _th_python_register_shortcut; "
                 "function py_probe() { _th_python_inspect \"$BUFFER\"; print -r --; print -r -- PY_STATUS:$_TH_PY_STATUS; print -r -- PY_MESSAGE:$_TH_PY_MESSAGE; print -r -- PY_PROPOSAL:${(qqq)_TH_PY_SUGGESTION}; print -r -- PY_DONE; }; "
                 "zle -N py_probe; bindkey '^Y' py_probe; "
                 "function py_tokens() { local -a parts; parts=( \"${(@z)BUFFER}\" ); print -r --; [[ \"${(Q)parts[1]}\" == \"$PWD/.venv/bin/python\" ]] && print -r -- PY_TARGET_OK; print -r -- PY_CURSOR:$CURSOR; print -r -- PY_LENGTH:${#BUFFER}; print -r -- PY_ACTIVE:$_TH_PY_ACTIVE; print -r -- PY_ARG1:${(Q)parts[5]}; print -r -- PY_ARG2:${(Q)parts[6]}; print -r -- PY_TOKENS_DONE; }; "
                 "zle -N py_tokens; bindkey '^T' py_tokens; print -r -- PY'_'TEST_READY\n")
        self.shell.send(setup)
        self.native_report = self.shell.wait_for('PY_TEST_READY\r\n')
        self.cd(self.project)

    def tearDown(self):
        self.shell.close()
        self.temp.cleanup()

    def executable(self, target):
        target.write_text('#!/bin/sh\nprintf EXECUTED >> ' + shlex.quote(str(self.sentinel)) + '\nexit 99\n')
        target.chmod(0o700)

    def environment(self, directory):
        env = directory / '.venv'
        (env / 'bin').mkdir(parents=True)
        (env / 'pyvenv.cfg').write_text(CFG)
        (env / 'bin/python').symlink_to(self.global_bin / 'python')
        for name in ('python3', 'pip', 'pip3'):
            self.executable(env / 'bin' / name)

    def state(self, enabled):
        target = self.base / 'state'
        target.write_text('terminal-helper-v1:' + ('on' if enabled else 'off') + '\n')
        target.chmod(0o600)

    def command(self, value):
        self.shell.send('\x15' + value + '\r')
        return self.shell.read()

    def cd(self, directory):
        self.command('builtin cd -- ' + shlex.quote(str(directory)))

    def inspect(self, text):
        self.shell.send('\x15' + text + '\x19')
        out = self.shell.wait_for('PY_DONE\r\n')
        statuses = re.findall(r'PY_STATUS:([a-z]+)', out)
        self.assertTrue(statuses, out)
        self.assertFalse(self.sentinel.exists(), 'Inspection executed a discovered binary')
        self.assertFalse((self.project / 'MUST_NOT_EXECUTE').exists(), 'Inspection executed typed shell syntax')
        return statuses[-1], out

    def request(self, text='pip install pandas', cursor=None):
        self.shell.send('\x15' + text)
        if cursor is not None:
            self.shell.send('\x1b[D' * (len(text) - cursor))
        self.shell.send(SHORTCUT)
        return self.shell.read(0.6)

    def test_native_default_shortcut_is_available_without_rebinding(self):
        # Captured immediately after source, before fixture-only keymap changes.
        self.assertIn('PY_NATIVE:emacs:installed', self.native_report)
        self.assertIn('_th_python_check', self.native_report)

    def test_doctor_does_not_mutate_or_disclose_macro_payloads(self):
        self.command("bindkey -M emacs -s '^X' 'PRIVATE_MACRO_PAYLOAD'; bindkey -M emacs '^X^P' undefined-key")
        out = self.command('_th_python_doctor')
        self.assertIn('binding/prefix conflict', out)
        self.assertNotIn('PRIVATE_MACRO_PAYLOAD', out)
        self.assertIn('PRIVATE_MACRO_PAYLOAD', self.command("bindkey -M emacs '^X'"))
        self.assertIn('undefined-key', self.command("bindkey -M emacs '^X^P'"))

    def test_mismatch_proposes_without_executing(self):
        status, out = self.inspect('pip install pandas')
        self.assertEqual(status, 'suggestion', out)
        self.assertIn('.venv/bin/python', out)
        self.assertIn('Resolved: pip ->', out)
        self.assertIn('Project candidate:', out)
        self.assertIn(str(self.project / '.venv'), out)
        self.assertIn('Mismatch:', out)
        self.assertIn('runtime health', out)
        self.assertIn('not validated', out)
        self.assertFalse(self.sentinel.exists())

    def test_match_resolution_does_not_rewrite(self):
        self.command('PATH=' + shlex.quote(str(self.project / '.venv/bin')) + ':$PATH')
        status, out = self.inspect('pip install pandas')
        self.assertEqual(status, 'match', out)
        self.assertIn('PY_PROPOSAL:""', out)
        self.assertIn('not validated', out)

    def test_missing_and_invalid_metadata(self):
        cfg = self.project / '.venv/pyvenv.cfg'
        cfg.unlink()
        self.assertEqual(self.inspect('pip install pandas')[0], 'missing')
        for value in ('version = 3.12.0\n', CFG + 'version = 3.12.0\n', CFG + 'prompt = evil\x1b[31m\n', 'x' * 4097):
            with self.subTest(value=repr(value[:40])):
                cfg.write_text(value)
                self.assertEqual(self.inspect('pip install pandas')[0], 'invalid')
        cfg.unlink()
        alternate = self.home / 'metadata'
        alternate.write_text(CFG)
        cfg.symlink_to(alternate)
        self.assertEqual(self.inspect('pip install pandas')[0], 'invalid')
        cfg.unlink()
        os.mkfifo(cfg)
        self.assertEqual(self.inspect('pip install pandas')[0], 'invalid')

    def test_missing_interpreter_and_environment_directory_symlink(self):
        interpreter = self.project / '.venv/bin/python'
        interpreter.unlink()
        self.assertEqual(self.inspect('pip install pandas')[0], 'missing')
        old = self.project / '.venv'
        moved = self.home / 'moved-env'
        old.rename(moved)
        old.symlink_to(moved, target_is_directory=True)
        self.assertEqual(self.inspect('pip install pandas')[0], 'invalid')

    def test_ambiguous_environment_shapes_and_active_other(self):
        sibling = self.project / 'venv'
        sibling.mkdir()
        (sibling / 'pyvenv.cfg').write_text(CFG)
        self.assertEqual(self.inspect('pip install pandas')[0], 'ambiguous')
        (sibling / 'pyvenv.cfg').unlink(); sibling.rmdir()
        self.command('VIRTUAL_ENV=' + shlex.quote(str(self.home / 'other')))
        self.assertEqual(self.inspect('python -m pip install pandas')[0], 'ambiguous')

    def test_alias_function_wrapper_prefixes_and_target_options_decline(self):
        self.command("alias pip='print ALIAS_MUST_NOT_RUN'")
        self.assertEqual(self.inspect('pip install pandas')[0], 'unsupported')
        self.command('unalias pip; function pip() { print FUNCTION_MUST_NOT_RUN; }')
        self.assertEqual(self.inspect('pip install pandas')[0], 'unsupported')
        self.command('unfunction pip')
        for text in ('sudo pip install pandas', 'env pip install pandas', 'uv pip install pandas',
                     'command pip install pandas', 'python -I -m pip install pandas',
                     'pip --python other install pandas', 'pip install --target=/tmp pandas',
                     'pip install -t/tmp pandas', 'pip install --prefix /tmp pandas',
                     'pip install --root /tmp pandas', 'pip install --python other pandas',
                     'pip install --user pandas'):
            with self.subTest(text=text):
                self.assertEqual(self.inspect(text)[0], 'unsupported')

    def test_target_abbreviations_and_short_clusters_leave_text_and_cursor(self):
        self.command('function py_same_buffer() { [[ "$BUFFER" == "$PY_EXPECTED" ]] && print -r -- PY_EXACT_MATCH; print -r -- PY_EXPECTED_CURSOR:$CURSOR; print -r -- PY_COMPARE_DONE; }; zle -N py_same_buffer; bindkey "^W" py_same_buffer')
        for text in ('pip install --tar=/tmp pandas', 'pip install --prefi=/tmp pandas',
                     'pip install --pref /tmp pandas', 'pip install -Ut/tmp pandas',
                     'pip install -qt /tmp pandas', 'pip install "--tar=/tmp" pandas',
                     "pip install '-Ut/tmp' pandas"):
            with self.subTest(text=text):
                self.command('typeset -g PY_EXPECTED=' + shlex.quote(text))
                cursor = len(text) - 3
                self.assertNotIn('Proposed:', self.request(text, cursor))
                out = self.shell.buffer()
                self.assertIn(':' + str(cursor), out)
                self.assertNotIn('.venv/bin/python', out)
                self.shell.send('\x17')
                exact = self.shell.wait_for('PY_COMPARE_DONE\r\n')
                self.assertIn('PY_EXACT_MATCH\r\n', exact)
                self.assertIn('PY_EXPECTED_CURSOR:' + str(cursor) + '\r\n', exact)
                self.shell.send('\x19')
                self.assertIn('PY_STATUS:unsupported', self.shell.wait_for('PY_DONE\r\n'))
                self.assertFalse(self.sentinel.exists())
        for text in ('pip install -U pandas', 'pip install --upgrade pandas'):
            self.assertEqual(self.inspect(text)[0], 'suggestion')

    def test_remote_and_runtime_overrides_decline_without_values(self):
        for name in ('SSH_CONNECTION', 'DEVCONTAINER', 'PIP_TARGET', 'PIP_PREFIX', 'PIP_ROOT', 'PIP_USER', 'PIP_CONFIG_FILE', 'PYTHONHOME', 'PYTHONPATH'):
            self.command(name + '=DO_NOT_DISPLAY_OVERRIDE_VALUE')
            status, out = self.inspect('pip install pandas')
            self.assertEqual(status, 'unsupported', out)
            self.assertNotIn('DO_NOT_DISPLAY_OVERRIDE_VALUE', out)
            self.command('unset ' + name)

    def test_unsupported_syntax_and_unbalanced_quotes_are_inert(self):
        for text in ('pip install $(touch MUST_NOT_EXECUTE)', 'pip install x; touch MUST_NOT_EXECUTE',
                     'pip install x | cat', 'pip install *', 'pip install "broken', "pip install 'broken",
                     'pip install broken\\'):
            self.assertEqual(self.inspect(text)[0], 'unsupported')
        self.command("function py_multiline() { BUFFER=$'pip install pandas\\ntouch MUST_NOT_EXECUTE'; CURSOR=${#BUFFER}; }; zle -N py_multiline; bindkey '^O' py_multiline")
        self.shell.send('\x0f\x19')
        self.assertIn('PY_STATUS:unsupported', self.shell.wait_for('PY_DONE\r\n'))
        self.assertFalse(self.sentinel.exists())

    def test_insert_only_and_escape_cursor_restore(self):
        text = 'pip install pandas tail'
        cursor = len(text) - 5
        self.assertIn('Proposed:', self.request(text, cursor))
        self.shell.send('\x1b')
        self.shell.read(0.6)
        self.assertIn('DUMP:"' + text + '":' + str(cursor), self.shell.buffer())
        self.shell.send('\x15')
        self.assertIn('Proposed:', self.request(text))
        self.shell.send('\r')
        out = self.shell.buffer()
        self.assertIn('.venv/bin/python', out)
        self.assertFalse(self.sentinel.exists())

    def test_space_unicode_apostrophe_hostile_path_and_raw_arguments(self):
        moved = self.home / "дані space '$(touch PY_EVIL)'"
        self.project.rename(moved); self.project = moved; self.cd(moved)
        text = 'pip install  \'package name\' "other name"'
        cursor = len(text) - 4
        self.assertIn('Proposed:', self.request(text, cursor))
        self.shell.send('\r\x14')
        out = self.shell.wait_for('PY_TOKENS_DONE\r\n')
        self.assertIn('PY_TARGET_OK', out)
        self.assertIn('PY_ARG1:package name', out)
        self.assertIn('PY_ARG2:other name', out)
        new_cursor = int(re.findall(r'PY_CURSOR:([0-9]+)', out)[-1])
        new_length = int(re.findall(r'PY_LENGTH:([0-9]+)', out)[-1])
        self.assertEqual(new_cursor, cursor + new_length - len(text))
        self.assertFalse(self.sentinel.exists())
        self.assertFalse((moved / 'PY_EVIL').exists())

    def test_metadata_binary_and_resolved_command_change_cancel(self):
        self.request()
        (self.project / '.venv/pyvenv.cfg').write_text(CFG + 'prompt = changed\n')
        self.shell.send('\r')
        self.assertIn('DUMP:"pip install pandas":18', self.shell.buffer())
        (self.project / '.venv/pyvenv.cfg').write_text(CFG)
        self.request()
        interpreter = self.project / '.venv/bin/python'
        interpreter.unlink(); self.executable(interpreter)
        self.shell.send('\r')
        self.assertIn('DUMP:"pip install pandas":18', self.shell.buffer())
        self.request()
        self.executable(self.global_bin / 'pip-new')
        (self.global_bin / 'pip-new').replace(self.global_bin / 'pip')
        self.shell.send('\r')
        self.assertIn('DUMP:"pip install pandas":18', self.shell.buffer())
        self.assertFalse(self.sentinel.exists())

    def test_cwd_change_rechecked_before_insert(self):
        other = self.home / 'other-project'; other.mkdir(); self.environment(other)
        self.command('function py_change_cwd() { builtin cd -- ' + shlex.quote(str(other)) + "; }; zle -N py_change_cwd; bindkey '^W' py_change_cwd")
        self.request()
        self.shell.send('\x17\r')
        self.assertIn('DUMP:"pip install pandas":18', self.shell.buffer())
        self.assertFalse(self.sentinel.exists())

    def test_off_before_check_and_before_insert(self):
        self.state(False)
        self.assertNotIn('Proposed:', self.request())
        self.assertIn('DUMP:"pip install pandas":18', self.shell.buffer())
        self.state(True)
        self.request()
        self.state(False)
        self.shell.send('\r')
        self.assertIn('DUMP:"pip install pandas":18', self.shell.buffer())
        self.assertFalse(self.sentinel.exists())

    def test_off_never_reads_environment_metadata(self):
        self.command('function _th_python_read_cfg() { print CFG_READER_MUST_NOT_RUN; return 1; }')
        self.state(False)
        out = self.request()
        self.assertNotIn('CFG_READER_MUST_NOT_RUN', out)
        self.assertNotIn('Proposed:', out)

    def test_editing_dismisses_and_custom_later_binding_is_preserved(self):
        self.command("function py_late_return() { print LATE_RETURN; zle .accept-line; }; zle -N py_late_return; function py_rebind() { bindkey -M emacs '^M' py_late_return; }; zle -N py_rebind; bindkey '^W' py_rebind")
        self.request()
        self.shell.send('\x17\x1b')
        self.shell.read(0.6)
        self.shell.send('\x15print NORMAL_AFTER_DISMISS\r')
        out = self.shell.read()
        self.assertIn('LATE_RETURN', out)
        self.assertIn('NORMAL_AFTER_DISMISS\r\n', out)
        self.request()
        self.shell.send('x\x14')
        out = self.shell.wait_for('PY_TOKENS_DONE\r\n')
        self.assertIn('PY_ACTIVE:0', out)
        self.assertIn('pandasx', self.shell.buffer())

    def test_tab_macro_delegates_after_dismiss_without_rewriting_user_map(self):
        self.command("bindkey -M emacs -s '^I' 'TAB_LITERAL'")
        self.request()
        self.shell.send('\t')
        out = self.shell.buffer()
        self.assertIn('pandasTAB_LITERAL', out)
        self.assertFalse(self.sentinel.exists())
        out = self.command("bindkey -M emacs -L '^I'")
        self.assertIn('TAB_LITERAL', out)

    def test_shortcut_respects_exact_parent_and_descendant_bindings(self):
        self.command("function py_other() { zle -M OTHER_BINDING; }; zle -N py_other; bindkey -M emacs '^X^P' py_other; _th_python_register_shortcut")
        out = self.command("bindkey -M emacs '^X^P'")
        self.assertIn('py_other', out)
        self.command("bindkey -M emacs '^X^P' undefined-key; bindkey -M emacs '^X' py_other; _th_python_register_shortcut")
        out = self.command("bindkey -M emacs '^X^P'")
        self.assertIn('undefined-key', out)
        self.command("bindkey -M emacs '^X' undefined-key; bindkey -M emacs '^X^Pz' py_other; _th_python_register_shortcut")
        out = self.command("bindkey -M emacs '^X^P'")
        self.assertIn('undefined-key', out)
        self.assertIn('py_other', self.command("bindkey -M emacs '^X^Pz'"))

    def test_macro_payload_cannot_impersonate_widget_ownership(self):
        for key in ('^X^P', '^X'):
            for payload in ('undefined-key', '_th_python_check'):
                with self.subTest(key=key, payload=payload):
                    self.command("bindkey -M emacs '^X' undefined-key; bindkey -M emacs '^X^P' undefined-key; bindkey -M emacs -s " + shlex.quote(key) + ' ' + shlex.quote(payload))
                    before = self.command("bindkey -M emacs -L " + shlex.quote(key))
                    self.command('_th_python_register_shortcut')
                    after = self.command("bindkey -M emacs -L " + shlex.quote(key))
                    self.assertIn('-s', before)
                    self.assertIn('-s', after)
                    self.assertIn(payload, after)
                    self.assertIn('binding/prefix conflict', self.command('_th_python_doctor'))

    def test_python3_and_pip3_simple_forms(self):
        for text in ('pip3 install pandas', 'python -m pip install pandas', 'python3 -m pip install pandas'):
            self.assertEqual(self.inspect(text)[0], 'suggestion')


def fixture_run(mode):
    fixture = PythonFixture()
    fixture.setUp()
    try:
        if mode == '--demo':
            proposed = fixture.request()
            fixture.shell.send('\r')
            inserted = fixture.shell.buffer()
            assert not fixture.sentinel.exists()
            return {'fixture': 'synthetic global command + local .venv; all interpreter files are inert sentinels',
                    'native_shortcut_report': fixture.native_report.replace(str(fixture.home), '<fixture>'),
                    'proposed': proposed.replace(str(fixture.home), '<fixture>'),
                    'after_insert_without_execution': inserted.replace(str(fixture.home), '<fixture>'),
                    'discovered_executables_ran': False}
        values = []
        for _ in range(30):
            fixture.shell.send('\x15pip install pandas'); fixture.shell.read(0.02)
            start = time.perf_counter()
            fixture.shell.send(SHORTCUT)
            data = b''
            deadline = start + 5
            while b'Escape: Dismiss' not in data:
                ready, _, _ = select.select([fixture.shell.fd], [], [], max(0, deadline-time.perf_counter()))
                if not ready: raise AssertionError('No visible Python context proposal within five seconds')
                data += os.read(fixture.shell.fd, 65536)
            values.append((time.perf_counter() - start) * 1000)
            fixture.shell.send('\x1b'); fixture.shell.read(0.5)
        assert not fixture.sentinel.exists()
        ordered = sorted(values[1:])
        return {'method': 'PTY Ctrl-X Ctrl-P to complete visible proposal/evidence; Escape dismisses; fixture maps deliberately free the shortcut',
                'native_shortcut_report': fixture.native_report.replace(str(fixture.home), '<fixture>'),
                'fixture': {'project_environments': 1, 'global_commands': 4, 'metadata_bytes': len(CFG.encode())},
                'repetitions': 30, 'first_ms': values[0], 'warm_p95_ms': ordered[min(len(ordered)-1, int(len(ordered)*.95))],
                'all_ms': values, 'discovered_executables_ran': False,
                'cold_limit': 'Fresh interactive shell/module load, OS/filesystem caches not flushed; all files remain synthetic.'}
    finally:
        fixture.tearDown()


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] in ('--benchmark', '--demo'):
        print(json.dumps(fixture_run(sys.argv[1]), ensure_ascii=True, indent=2))
    else:
        unittest.main(verbosity=2)
