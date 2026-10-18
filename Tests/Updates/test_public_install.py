"""Remote-only smoke of the real production CLI against the currently published release."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

assert os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_OS") == "macOS", "Use a disposable GitHub macOS runner."
home = Path.home()
target = home / "Applications/Terminal Helper.app"
support = home / "Library/Application Support/Terminal Helper"
assert not target.exists() and not target.is_symlink() and not support.exists() and not support.is_symlink(), "Refusing an existing installation."
source = Path("dist/Terminal Helper.app").resolve()
target.parent.mkdir(mode=0o700, exist_ok=True)
shutil.copytree(source, target, copy_function=shutil.copy2)
exe = target / "Contents/MacOS/TerminalHelper"
backup = None
download = None
config = home / ".zshrc"
config_before = config.read_bytes() if config.exists() else None
try:
    # VERSION=0.1.0 builds current updater code as an older-version fixture, not a historical binary.
    with (target / "Contents/Info.plist").open("rb") as stream:
        assert plistlib.load(stream)["CFBundleShortVersionString"] == "0.1.0"
    support.mkdir(mode=0o700, parents=True)
    integration = source / "Contents/Resources/Integration/terminal-helper.zsh"
    for name, data in {
        "integration.zsh": integration.read_bytes(),
        "app-path": (str(target) + "\n").encode(),
        "state": b"terminal-helper-v1:on\n",
    }.items():
        file = support / name
        file.write_bytes(data)
        file.chmod(0o600)
    run = subprocess.run([str(exe), "--update"], capture_output=True, text=True, timeout=360)
    print(run.stdout)
    if run.returncode:
        print(run.stderr)
    assert run.returncode == 0, "Production update CLI failed; retain this run's diagnostics."
    match = re.search(r"^Verified SHA-256\. Saved to (.+)$", run.stdout, re.M)
    assert match, "No verified download recorded."
    download = Path(match.group(1))
    assert download.parent.parent == home / "Downloads" and download.parent.name.startswith("Terminal Helper ")
    match = re.search(r"^Installed Terminal Helper ([0-9.]+)\. Previous app: (.+)$", run.stdout, re.M)
    assert match, "No installed version/recovery copy recorded."
    version, backup_path = match.groups()
    backup = Path(backup_path)
    assert backup.parent.parent == target.parent and backup.parent.name.startswith(".Terminal-Helper-update-")
    with (target / "Contents/Info.plist").open("rb") as stream:
        assert plistlib.load(stream)["CFBundleShortVersionString"] == version
    with (backup / "Contents/Info.plist").open("rb") as stream:
        assert plistlib.load(stream)["CFBundleShortVersionString"] == "0.1.0"
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(target)], check=True)
    assert os.getxattr(target, "com.apple.quarantine")
    assert os.getxattr(exe, "com.apple.quarantine")
    assert (support / "state").read_bytes() == b"terminal-helper-v1:off\n"
    assert (support / "integration.zsh").read_bytes() == (target / "Contents/Resources/Integration/terminal-helper.zsh").read_bytes()
    assert (support / "app-path").read_bytes() == (str(target) + "\n").encode()
    assert (config.read_bytes() if config.exists() else None) == config_before
    result = {
        "production_terminal_update": "PASS",
        "published_version": version,
        "download_sha256": hashlib.sha256(download.read_bytes()).hexdigest(),
        "signature_integrity": "PASS",
        "installed_bundle_and_executable_quarantine": "PASS",
        "retained_previous_app": "PASS",
        "off_and_exact_owned_integration": "PASS",
        "shell_configuration_preserved": "PASS",
        "launch_request": "Launch Services only; macOS approval remains manual",
        "method": "Current updater source built with VERSION=0.1.0 as an older-version fixture; anonymous production GitHub download, actual in-place install. Not a historical v0.1 binary.",
    }
    Path("results").mkdir(exist_ok=True)
    Path("results/public-install.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
finally:
    subprocess.run(["/usr/bin/pkill", "-TERM", "-f", "^" + re.escape(str(exe)) + "( |$)"], check=False)
    time.sleep(0.5)
    shutil.rmtree(target, ignore_errors=True)
    shutil.rmtree(support, ignore_errors=True)
    if backup is not None:
        shutil.rmtree(backup.parent, ignore_errors=True)
    if download is not None:
        shutil.rmtree(download.parent, ignore_errors=True)
