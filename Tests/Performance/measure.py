#!/usr/bin/env python3
"""Remote-runner measurements, not a claim about a user's terminal."""
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
RESULTS = ROOT / "results"
RESULTS.mkdir(exist_ok=True)

def percentile(values, fraction=.95):
    return sorted(values)[max(0, int(len(values) * fraction + .999999) - 1)]

def launch_ms(script, env):
    started = time.perf_counter()
    subprocess.run(["/bin/zsh", "-d", "-f", "-i", "-c", script], env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return (time.perf_counter() - started) * 1000

with tempfile.TemporaryDirectory(prefix="terminal-helper-measure-") as temporary:
    env = dict(os.environ, HOME=temporary, ZDOTDIR=temporary)
    # Existing compinit is identical in both arms; integration startup does not generate suggestions.
    base = "autoload -Uz compinit; compinit -D; exit"
    source = str(ROOT / "Integration" / "terminal-helper.zsh").replace("'", "'\\''")
    integrated = "autoload -Uz compinit; compinit -D; source '" + source + "'; exit"
    cold = {"baseline_ms": launch_ms(base, env), "integrated_ms": launch_ms(integrated, env)}
    baseline, enabled = [], []
    for repetition in range(40):
        # Alternate ordering to reduce systematic cache/order bias.
        if repetition % 2:
            enabled.append(launch_ms(integrated, env)); baseline.append(launch_ms(base, env))
        else:
            baseline.append(launch_ms(base, env)); enabled.append(launch_ms(integrated, env))
    added = [e-b for b, e in zip(baseline, enabled)]
    startup = {"repetitions": 40, "method": "paired fresh zsh -d -f -i subprocesses; identical compinit -D; wall-clock; no cache flush",
               "cold_first_observation": cold, "baseline_p95_ms": percentile(baseline),
               "integrated_p95_ms": percentile(enabled), "paired_added_p95_ms": percentile(added),
               "paired_added_median_ms": statistics.median(added), "target_added_p95_ms": 30}
    startup["target_met_on_runner"] = startup["paired_added_p95_ms"] <= 30

app = ROOT / "dist" / "Terminal Helper.app" / "Contents" / "MacOS" / "TerminalHelper"
subprocess.run([str(app), "--ui-smoke-test", str(RESULTS / "native-settings.png")], check=True, timeout=20)
process = subprocess.Popen([str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
samples = []
try:
    time.sleep(2)
    assert process.poll() is None, "Controller exited before idle measurement"
    for _ in range(6):
        row = subprocess.check_output(["/bin/ps", "-o", "rss=,%cpu=", "-p", str(process.pid)], text=True).split()
        children = subprocess.run(["/usr/bin/pgrep", "-P", str(process.pid)], capture_output=True, text=True)
        samples.append({"rss_kib": int(row[0]), "cpu_percent": float(row[1]),
                        "direct_child_count": len(children.stdout.splitlines())})
        time.sleep(1)
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait()
report = {
    "platform": platform.platform(), "architecture": platform.machine(),
    "hardware": subprocess.check_output(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
    "startup": startup,
    "controller_off": {"method": "fresh controller, no integration installed/state enabled, 2s settle, six 1s ps RSS/%CPU samples; %CPU is OS process average",
                       "samples": samples, "process_count": 1,
                       "rss_median_kib": statistics.median(s["rss_kib"] for s in samples),
                       "cpu_max_percent": max(s["cpu_percent"] for s in samples),
                       "owned_children_max": max(s["direct_child_count"] for s in samples)},
    "app_bytes": sum(p.stat().st_size for p in app.parents[2].rglob("*") if p.is_file()),
    "limits": ["No forced disk-cache flush; first observation is not a guaranteed cold filesystem.",
               "Native Settings render is real AppKit, not a Terminal.app/VoiceOver end-to-end test.",
               "Network/slow filesystems and third-party completion functions can exceed timing targets.",
               "Completion latency is measured separately by the ZLE PTY benchmark."]
}
(RESULTS / "performance.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
