# Verification and compatibility

Use the exact source commit in each Actions artifact name. Only a successful complete CI run counts as validation. A packaged app from a failed or cancelled run is diagnostic evidence, not a validated build. The current PR description records final numeric results and exact artifact links; each artifact also contains the underlying JSON and logs. Artifact retention is 14 days.

## Automated evidence

The MVP workflow runs on GitHub-hosted macOS 15 Apple Silicon and Intel, with contents-read permission, no persisted checkout credentials, pinned Actions, explicit pipefail, and a 20-minute timeout. All project checkouts, generated files, builds, disk fixtures and app execution occur on disposable remote runners.

- Actual PTY/ZLE tests exercise files, directory typos, quoting, Unicode, control and malicious-looking filenames, ambiguous selection, Escape snapshots, acceptance without execution, custom keys, unsupported expressions, multiline and bracketed-paste input, cursor-middle edits, and state changes across multiple shells.
- Installer tests cover repeat install/uninstall, custom ZDOTDIR, exact byte preservation without final newline, backups, unsafe symlinks, missing integration repair, and malformed/reversed markers.
- A temporary case-sensitive HFSX image on the runner exercises the case-specific path test; the default runner filesystem test may skip because it is case-insensitive.
- A universal native app is built and ad-hoc signed/verified. State self-tests check On/Off/re-enable, exact bytes, malformed state, permissions and symlinks.
- A controller lifecycle test invokes actual toggle and Disable and Quit actions against isolated temporary state.
- The real native Settings content is rendered to PNG for visual review. This is a view render, not a screen recording or proof of every menu/assistive-technology behavior.

The first strictly validated shell run at [ba81b5b](https://github.com/denysshcherbak4/terminal-helper/commit/ba81b5b2377b0781fc1bd1ed7fcddeca42cd31e1) passed 27 PTY tests (one case-sensitive skip) and four installer tests on each architecture. That complete run failed in the native render exporter. Later runs add the bracketed-paste and dedicated case-volume checks and correct the exporter; consult the final PR/run status rather than treating the earlier run as fully green.

## Measurement method

Startup: 40 paired fresh `zsh -d -f -i` subprocesses per condition, with identical `compinit -D`; alternating order reduces systematic cache bias. Report baseline/integrated p95 and p95 of paired added time. First observations are recorded separately; no filesystem cache flush is performed.

Completion: actual PTY Tab to a visible useful filename, 256 ordinary fixture files plus the private state directory, 30 repetitions. The warm benchmark initializes completion before timing. A separate benchmark uses 30 fresh shells with no `compinit` setup and includes its first-Tab cost. Do not apply warm results to an unconfigured beginner shell.

At ba81b5b the configured-shell first observation was 26.24 ms (Apple M1 virtual runner) / 30.34 ms (Intel runner); warm p95 was 10.38 / 9.82 ms. These are fixture observations, not universal latency claims. Fresh-shell results, final startup and controller measurements are in the validated artifact and final PR table.

Idle controller: allow a two-second settle, take six one-second RSS/CPU/child-process samples, and calculate CPU consumed over the settled sample interval. OS `ps %CPU` may include process startup; the interval value is the idle measurement. Record logical app bytes, compressed ZIP bytes, hardware, OS, shell, Swift version, and signature status.

Targets: added startup p95 ≤30 ms, first useful suggestion p95 ≤100 ms. Report misses directly. Native/user completion can enumerate large directories or execute trusted completion logic; slow/network filesystems can exceed these targets. Fuzzy enumeration stops after 257 entries, declines above 256 siblings, limits results to 20, and does not recurse.

## Support matrix

| Environment | Evidence and limit |
| --- | --- |
| macOS 15, Apple Silicon and Intel, zsh 5.9 | Automated PTY, native compilation/state/lifecycle, fixture and measurement jobs; exact results in the selected run. |
| macOS 13 minimum | Deployment target and selected API availability; oldest-OS runtime validation remains manual. |
| Terminal.app | Primary intended terminal; generic PTY testing covers real ZLE, but the actual Terminal.app user flow remains a manual release check. |
| iTerm2 | Not manually validated; no compatibility claim beyond the shared zsh/PTTY mechanism. |
| Case-insensitive filesystem | Default runner fixtures. |
| Case-sensitive filesystem | Dedicated runner-owned HFSX fixture; case-sensitive APFS still merits manual testing. |
| Custom ZDOTDIR | Explicit folder selection in Settings, with installer fixture containing spaces. |
| Custom key macros / unsupported syntax | Safe refusal/fallback; no broad shell parser. |
| Missing intermediate path ancestors | Correction is final-component only; leaves unsupported paths intact. |
| Developer ID / notarization | Not configured. Ad-hoc integrity signing does not establish Gatekeeper trust. |

## Reviews and release checks

The shell, native app, installer, build/CI, and adjacent callers were read through GitHub APIs by an independent reviewer. Ponytail review and Apple native design guidance were applied. Rendered affordance/typography review uses the actual native PNG.

The formal Codex Security workflow requires a resolved local Git checkout and revision range. That conflicts with the authorized remote-only boundary, so it was not run; independent remote source review is the explicit substitute, not a claimed formal scan.

See [manual verification](MANUAL-VERIFICATION.md) for actual Terminal.app/iTerm2, VoiceOver, appearances, oldest macOS, slow filesystems, install interruption, and release-distribution checks. No public release or personal-Mac installation is implied by a successful CI build.
