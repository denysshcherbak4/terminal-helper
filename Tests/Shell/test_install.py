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

if __name__ == '__main__':
    unittest.main(verbosity=2)
