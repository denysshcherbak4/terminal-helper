#!/usr/bin/env python3
"""Optional real Terminal.app smoke, only for a disposable macOS CI runner."""
import json
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def report(status, reason):
    print(json.dumps({'status': status, 'reason': reason,
                      'method': 'Terminal.app AppleScript; isolated zsh; queued ZLE keys; no global keyboard automation'}), flush=True)
    return 1 if status == 'FAIL' else 0


def main():
    if platform.system() != 'Darwin':
        return report('SKIP', 'Terminal.app requires a macOS GUI session.')
    with tempfile.TemporaryDirectory(prefix='terminal-helper-native-') as tmp:
        home = Path(tmp)
        (home / 'Documents').mkdir()
        base = home / 'Library/Application Support/Terminal Helper'
        base.mkdir(parents=True, mode=0o700)
        state = base / 'state'
        state.write_text('terminal-helper-v1:on\n')
        state.chmod(0o600)
        source_path = shlex.quote(str(ROOT / 'Integration/terminal-helper.zsh'))
        (home / '.zshrc').write_text(r"""
PROMPT='Terminal Helper CI> '
RPROMPT=''
HISTFILE=/dev/null
cd -- "$HOME" || exit 1
autoload -Uz compinit
compinit -D || exit 1
source SOURCE_PATH
function terminal_helper_smoke_verify() {
  local outcome=FAIL
  [[ "$BUFFER" == cd\ *Documents* && "$PWD" == "$HOME" ]] && (( CURSOR == $#BUFFER )) && outcome=PASS
  print -r -- "$outcome" > "$HOME/result"
  # Deliberate test cleanup executes only this constant exit command.
  BUFFER=exit
  CURSOR=4
  zle .accept-line
}
zle -N terminal_helper_smoke_verify
bindkey '^]' terminal_helper_smoke_verify
typeset -g terminal_helper_smoke_queued=0
function terminal_helper_smoke_queue() {
  (( terminal_helper_smoke_queued )) && return 0
  terminal_helper_smoke_queued=1
  zle -U $'cd ~/Doc\t\r\035'
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init terminal_helper_smoke_queue
""".replace('SOURCE_PATH', source_path))
        launch = 'exec /usr/bin/env HOME=' + shlex.quote(tmp) + ' ZDOTDIR=' + shlex.quote(tmp) + ' /bin/zsh -d -i'
        # Identify our empty tab before starting a shell that might finish quickly.
        script = """tell application "Terminal"
set ownedTab to do script ""
set ownedTTY to tty of ownedTab
set ownedID to 0
repeat with candidateWindow in windows
  repeat with candidateTab in tabs of candidateWindow
    if ownedTTY is not "" and tty of candidateTab is ownedTTY then set ownedID to id of candidateWindow
  end repeat
end repeat
if ownedID is 0 then error "Could not identify the test-owned Terminal window"
do script LAUNCH_COMMAND in ownedTab
return ownedID
end tell""".replace('LAUNCH_COMMAND', json.dumps(launch))
        try:
            opened = subprocess.run(['/usr/bin/osascript', '-e', script], capture_output=True, text=True, timeout=15)
        except subprocess.TimeoutExpired:
            return report('SKIP', 'Terminal.app AppleEvents/display session did not respond within 15 seconds; native interaction remains unverified.')
        if opened.returncode:
            reason = opened.stderr.strip()[:350]
            unavailable = any(code in reason for code in ('-1743', '-10810', '-600', '-609', '-1712', 'not authorized', 'not permitted'))
            return report('SKIP' if unavailable else 'FAIL', 'Terminal.app launch unavailable: ' + reason)
        try:
            window_id = int(opened.stdout.strip())
        except ValueError:
            return report('FAIL', 'Terminal.app did not return its test-owned window identity.')
        status, reason = 'FAIL', 'No verification result within 12 seconds.'
        try:
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                result = home / 'result'
                if result.exists():
                    passed = result.read_text().strip() == 'PASS'
                    status = 'PASS' if passed else 'FAIL'
                    reason = ('Real Terminal.app Tab followed by Enter edited the buffer while preserving the working directory.'
                              if passed else 'Terminal.app completion failed its buffer, cursor, or unchanged-directory assertion.')
                    time.sleep(0.1)
                    break
                time.sleep(0.05)
        finally:
            close = 'tell application "Terminal" to if exists window id ' + str(window_id) + ' then close window id ' + str(window_id)
            try:
                closed = subprocess.run(['/usr/bin/osascript', '-e', close], capture_output=True, text=True, timeout=3)
                if closed.returncode:
                    status, reason = 'FAIL', 'Could not close the test-owned Terminal window.'
            except subprocess.TimeoutExpired:
                status, reason = 'FAIL', 'Closing the test-owned Terminal window timed out.'
        return report(status, reason)


if __name__ == '__main__':
    sys.exit(main())
