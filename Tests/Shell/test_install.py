#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]

class InstallationTests(unittest.TestCase):
    def test_roundtrip_zdotdir_bytes_and_repetition(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            zdot = home / 'custom shell'
            zdot.mkdir()
            config = zdot / '.zshrc'
            original = 'export ORIGINAL="дані and spaces"\n# no final newline'.encode()
            config.write_bytes(original)
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(zdot)}
            def run(script):
                subprocess.run(['/bin/zsh', str(ROOT / 'Integration' / script)], env=env, check=True, capture_output=True)
            run('install.zsh')
            once = config.read_bytes()
            run('install.zsh')
            self.assertEqual(config.read_bytes(), once)
            self.assertEqual(once.count(b'# >>> Terminal Helper'), 1)
            run('uninstall.zsh')
            self.assertEqual(config.read_bytes(), original)
            run('uninstall.zsh')
            self.assertEqual(config.read_bytes(), original)
            self.assertTrue(list(zdot.glob('.zshrc.terminal-helper-backup.*')))

    def test_symlink_config_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            target = home / 'important'
            target.write_text('untouched')
            (home / '.zshrc').symlink_to(target)
            result = subprocess.run(['/bin/zsh', str(ROOT / 'Integration/install.zsh')], env={**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home)}, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), 'untouched')

    def test_partial_block_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.zshrc'
            original = b'# >>> Terminal Helper managed integration >>>\n'
            config.write_bytes(original)
            result = subprocess.run(['/bin/zsh', str(ROOT / 'Integration/install.zsh')], env={**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home)}, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(config.read_bytes(), original)

    def test_reversed_block_rejected_and_upgrade_repaired(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.zshrc'
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home)}
            original = b'# <<< Terminal Helper managed integration <<<\n# >>> Terminal Helper managed integration >>>\nKEEP=1'
            config.write_bytes(original)
            result = subprocess.run(['/bin/zsh', str(ROOT / 'Integration/uninstall.zsh')], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(config.read_bytes(), original)
            config.write_text('KEEP=1')
            script = str(ROOT / 'Integration/install.zsh')
            subprocess.run(['/bin/zsh', script], env=env, check=True, capture_output=True)
            installed = home / 'Library/Application Support/Terminal Helper/integration.zsh'
            installed.write_text('# old integration\n')
            subprocess.run(['/bin/zsh', script], env=env, check=True, capture_output=True)
            self.assertEqual(installed.read_bytes(), (ROOT / 'Integration/terminal-helper.zsh').read_bytes())
            installed.unlink()
            subprocess.run(['/bin/zsh', script], env=env, check=True, capture_output=True)
            self.assertTrue(installed.is_file())

    def test_busy_lifecycle_lock_never_changes_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.zshrc'
            config.write_bytes(b'KEEP=1')
            base = home / 'Library/Application Support/Terminal Helper'
            (base / '.integration-lock').mkdir(parents=True)
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home)}
            for name in ('install.zsh', 'uninstall.zsh'):
                result = subprocess.run(['/bin/zsh', str(ROOT / 'Integration' / name)], env=env, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config.read_bytes(), b'KEEP=1')
            self.assertTrue((base / '.integration-lock').is_dir())

    def test_modes_readonly_and_nonregular_owned_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.zshrc'
            config.write_bytes(b'KEEP=1')
            config.chmod(0o400)
            base = home / 'Library/Application Support/Terminal Helper'
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home)}
            install = ['/bin/zsh', str(ROOT / 'Integration/install.zsh')]
            result = subprocess.run(install, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(config.read_bytes(), b'KEEP=1')
            self.assertEqual(config.stat().st_mode & 0o777, 0o400)
            self.assertFalse((base / '.integration-lock').exists(), result.stderr.decode(errors='replace'))
            config.chmod(0o640)
            (base / 'integration.zsh').mkdir()
            result = subprocess.run(install, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(config.read_bytes(), b'KEEP=1')
            self.assertFalse((base / '.integration-lock').exists(), result.stderr.decode(errors='replace'))
            (base / 'integration.zsh').rmdir()
            result = subprocess.run(install, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors='replace'))
            self.assertEqual(config.stat().st_mode & 0o777, 0o640)
            subprocess.run(['/bin/zsh', str(ROOT / 'Integration/uninstall.zsh')], env=env, check=True, capture_output=True)
            self.assertEqual(config.read_bytes(), b'KEEP=1')
            self.assertEqual(config.stat().st_mode & 0o777, 0o640)
            self.assertFalse((base / '.integration-lock').exists())

    def test_app_path_record_install_repair_and_uninstall(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.zshrc'
            config.write_bytes(b'KEEP=1')
            apps = []
            for name in ('Terminal Helper Дані.app', 'Updated Helper Дані.app'):
                app = home / name
                binary = app / 'Contents/MacOS/TerminalHelper'
                binary.parent.mkdir(parents=True)
                binary.write_text('#!/bin/zsh -f\nexit 0\n')
                binary.chmod(0o700)
                apps.append(app)
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home),
                   'TERMINAL_HELPER_APP_PATH': str(apps[0])}
            install = ['/bin/zsh', str(ROOT / 'Integration/install.zsh')]
            result = subprocess.run(install, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            marker = home / 'Library/Application Support/Terminal Helper/app-path'
            self.assertEqual(marker.read_text(), str(apps[0]) + '\n')
            self.assertEqual(marker.stat().st_mode & 0o7777, 0o600)
            configured = config.read_bytes()
            marker.write_text('broken')
            marker.chmod(0o644)
            env['TERMINAL_HELPER_APP_PATH'] = str(apps[1])
            result = subprocess.run(install, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(marker.read_text(), str(apps[1]) + '\n')
            self.assertEqual(marker.stat().st_mode & 0o7777, 0o600)
            self.assertEqual(config.read_bytes(), configured)
            result = subprocess.run(['/bin/zsh', str(ROOT / 'Integration/uninstall.zsh')], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertFalse(marker.exists())
            self.assertEqual(config.read_bytes(), b'KEEP=1')
            self.assertTrue((apps[0] / 'Contents/MacOS/TerminalHelper').exists())

    def test_invalid_app_metadata_is_rejected_before_config_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.zshrc'
            config.write_bytes(b'KEEP=1')
            env = {**os.environ, 'HOME': str(home), 'ZDOTDIR': str(home)}
            install = ['/bin/zsh', str(ROOT / 'Integration/install.zsh')]
            for value in ('', 'relative.app', '/tmp/not-a-bundle', '/tmp/bad\n.app', '/tmp/bad\x1b.app'):
                result = subprocess.run(install, env={**env, 'TERMINAL_HELPER_APP_PATH': value}, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config.read_bytes(), b'KEEP=1')
            base = home / 'Library/Application Support/Terminal Helper'
            target = home / 'untouched-marker'
            target.write_text('KEEP')
            (base / 'app-path').symlink_to(target)
            for name in ('install.zsh', 'uninstall.zsh'):
                result = subprocess.run(['/bin/zsh', str(ROOT / 'Integration' / name)], env=env, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config.read_bytes(), b'KEEP=1')
                self.assertEqual(target.read_text(), 'KEEP')

if __name__ == '__main__':
    unittest.main(verbosity=2)
