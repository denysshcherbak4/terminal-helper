#!/usr/bin/env python3
"""Explicit shell management commands use only their recorded app bundle."""
import os
import re
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ManagementCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.base = self.home / 'Library/Application Support/Terminal Helper'
        self.base.mkdir(parents=True, mode=0o700)
        self.app = self.home / 'Terminal Helper Дані.app'
        self.binary = self.app / 'Contents/MacOS/TerminalHelper'
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text('#!/bin/zsh -f\nprint -r -- "stub:$#:$1"\nprint -r -- "$1" >> "$HOME/cli-calls"\n')
        self.binary.chmod(0o700)
        self.marker = self.base / 'app-path'
        self.write_marker(str(self.app) + '\n')
        (self.base / 'state').write_text('terminal-helper-v1:off\n')
        (self.base / 'state').chmod(0o600)
        self.env = {**os.environ, 'HOME': str(self.home), 'ZDOTDIR': str(self.home)}
        self.env.pop('TERMINAL_HELPER_APP_PATH', None)

    def tearDown(self):
        self.temp.cleanup()

    def write_marker(self, value):
        self.marker.write_bytes(value.encode() if isinstance(value, str) else value)
        self.marker.chmod(0o600)

    def shell(self, code, before=''):
        script = before + '\nsource ' + shlex.quote(str(ROOT / 'Integration/terminal-helper.zsh')) + '\n' + code
        return subprocess.run(['/bin/zsh', '-d', '-f', '-i', '-c', script],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_explicit_commands_work_while_off(self):
        for command, flag in [('version', '--version'), ('check', '--check-for-updates'), ('update', '--update')]:
            result = self.shell('terminal-helper ' + command)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('stub:1:' + flag, result.stdout)
        self.assertEqual((self.home / 'cli-calls').read_text().splitlines(),
                         ['--version', '--check-for-updates', '--update'])

    def test_missing_malformed_and_control_records_never_execute(self):
        self.marker.unlink()
        result = self.shell('terminal-helper version')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('reinstall shell integration', result.stderr)
        for value in ('', str(self.app), str(self.app) + '\n\n', 'relative.app\n',
                      str(self.app) + '\r\n', '/missing.app\n', '/not-a-bundle\n',
                      str(self.app) + '\x00\n'):
            self.write_marker(value)
            result = self.shell('terminal-helper version')
            self.assertNotEqual(result.returncode, 0, repr(value))
        self.assertFalse((self.home / 'cli-calls').exists())

    def test_marker_and_base_permissions_and_symlinks_rejected(self):
        self.marker.chmod(0o644)
        self.assertNotEqual(self.shell('terminal-helper check').returncode, 0)
        self.marker.chmod(0o600)
        self.base.chmod(0o755)
        self.assertNotEqual(self.shell('terminal-helper check').returncode, 0)
        self.base.chmod(0o700)
        target = self.home / 'other-marker'
        target.write_text(str(self.app) + '\n')
        target.chmod(0o600)
        self.marker.unlink()
        self.marker.symlink_to(target)
        self.assertNotEqual(self.shell('terminal-helper check').returncode, 0)
        self.assertFalse((self.home / 'cli-calls').exists())

    def test_arguments_cannot_forward_commands_or_extra_flags(self):
        for arguments in ('', 'version extra', shlex.quote('check; touch INJECTED'), '--update'):
            result = self.shell('terminal-helper ' + arguments)
            self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse((self.home / 'cli-calls').exists())
        self.assertFalse((self.home / 'INJECTED').exists())

    def test_shell_looking_app_path_is_literal(self):
        malicious = self.home / 'App $(touch INJECTED) Дані.app'
        self.app.rename(malicious)
        self.write_marker(str(malicious) + '\n')
        result = self.shell('terminal-helper version')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('stub:1:--version', result.stdout)
        self.assertFalse((self.home / 'INJECTED').exists())

    def test_known_executable_must_not_be_symlink_and_status_is_preserved(self):
        target = self.home / 'other-binary'
        self.binary.rename(target)
        self.binary.symlink_to(target)
        self.assertNotEqual(self.shell('terminal-helper update').returncode, 0)
        self.binary.unlink()
        self.binary.write_text('#!/bin/zsh -f\nexit 7\n')
        self.binary.chmod(0o700)
        self.assertEqual(self.shell('terminal-helper version').returncode, 7)

    def test_existing_alias_function_and_command_are_preserved(self):
        result = self.shell('whence -w terminal-helper', "alias terminal-helper='print ALIAS'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('terminal-helper: alias', result.stdout)
        result = self.shell('terminal-helper version', 'function terminal-helper { print EXISTING_FUNCTION; }')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EXISTING_FUNCTION', result.stdout)
        directory = self.home / 'bin'
        directory.mkdir()
        existing = directory / 'terminal-helper'
        existing.write_text('#!/bin/zsh -f\nprint EXISTING_COMMAND\n')
        existing.chmod(0o700)
        self.env['PATH'] = str(directory) + os.pathsep + self.env['PATH']
        result = self.shell('terminal-helper version')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EXISTING_COMMAND', result.stdout)
        self.assertFalse((self.home / 'cli-calls').exists())

    def test_management_function_survives_unsupported_key_macro(self):
        result = self.shell('terminal-helper version', "bindkey -s '^M' 'MACRO_LITERAL'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('stub:1:--version', result.stdout)

    def test_doctor_reports_live_shell_without_running_recorded_app(self):
        plist = self.app / 'Contents/Info.plist'
        plist.write_text('<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>0.3.3</string></dict></plist>')
        result = self.shell('terminal-helper doctor')
        self.assertEqual(result.returncode, 0, result.stderr)
        integration = (ROOT / 'Integration/terminal-helper.zsh').read_text()
        version = re.search(r'^typeset -gr _TH_INTEGRATION_VERSION=(\\S+)$', integration, re.M).group(1)
        self.assertIn('Terminal Helper integration: ' + version, result.stdout)
        self.assertIn('Shared state: Off', result.stdout)
        self.assertIn('App version: 0.3.3 (recorded app metadata)', result.stdout)
        self.assertIn('emacs Tab:', result.stdout)
        self.assertIn('viins Tab:', result.stdout)
        self.assertFalse((self.home / 'cli-calls').exists())

    def test_doctor_handles_missing_malformed_state_and_app_marker(self):
        for value in ('bad', 'terminal-helper-v1:on\nextra'):
            (self.base / 'state').write_text(value)
            self.write_marker('/bad\nmetadata.app\n')
            result = self.shell('terminal-helper doctor')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('invalid or missing (helper disabled)', result.stdout)
            self.assertIn('App version: unavailable', result.stdout)
        self.assertFalse((self.home / 'cli-calls').exists())

    def test_doctor_survives_unsafe_accept_macro_and_hides_payload(self):
        result = self.shell('terminal-helper doctor',
                            "bindkey -M emacs -s '^M' 'PRIVATE_MACRO_CONTENT'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('not installed:', result.stdout)
        self.assertNotIn('PRIVATE_MACRO_CONTENT', result.stdout)

    def test_doctor_reports_later_plugin_conflict_and_preserves_accept_line(self):
        result = self.shell("bindkey -M emacs '^I' complete-word; terminal-helper doctor; print -r -- ACCEPT_WIDGET:$widgets[accept-line]")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('conflict: a later binding owns Tab', result.stdout)
        self.assertIn('ACCEPT_WIDGET:builtin', result.stdout)



if __name__ == '__main__':
    unittest.main(verbosity=2)
