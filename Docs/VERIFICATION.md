# Verification and compatibility

Use the exact source commit in each Actions artifact name. Only a successful complete CI run counts as validation. A packaged app from a failed or cancelled run is diagnostic evidence, not a validated build. The current PR description records final numeric results and exact artifact links; each artifact also contains the underlying JSON and logs. Artifact retention is 14 days.

## Automated evidence

The MVP workflow runs on GitHub-hosted macOS 15 Apple Silicon and Intel, with contents-read permission, no persisted checkout credentials, pinned Actions, explicit pipefail, and a 20-minute timeout. All project checkouts, generated files, builds, disk fixtures and app execution occur on disposable remote runners.

- Actual PTY/ZLE tests exercise files, directory typos, quoting, Unicode, control and malicious-looking filenames, ambiguous selection, Escape snapshots, acceptance without execution, custom keys, unsupported expressions, multiline and bracketed-paste input, cursor-middle edits, and state changes across multiple shells.
- Installer tests cover repeat install/uninstall, custom ZDOTDIR, exact bytes, backups, unsafe symlinks, missing integration repair, partial/reversed blocks and private app-path metadata.
- Terminal management fixtures cover Off-independent version/check/update, exact arguments, quoting, unsafe marker/path refusal and existing-command preservation.
- Native update tests use offline metadata and a real URLSession delegate: versions, repository/tag assets, redirects, sizes, HTTP failures, checksums, private unique files and macOS quarantine.
- A temporary case-sensitive HFSX image on the runner exercises the case-specific path test; the default runner filesystem test may skip because it is case-insensitive.
- A universal native app is built and ad-hoc signed/verified. State self-tests check On/Off/re-enable, exact bytes, malformed state, permissions and symlinks.
- A controller lifecycle test invokes actual toggle and Disable and Quit actions against isolated temporary state. Native Settings assertions check install-first controls and On/Off state.
- An actual Terminal.app smoke test uses AppleScript to open its own isolated interactive zsh session and queues ZLE keys. It asserts Tab/Enter changes the buffer without changing the working directory. AppleEvents/display unavailability is explicitly recorded as SKIP; a failed assertion fails CI. This does not replace the human terminal/keyboard checklist.
- The real native Settings content is rendered to PNG for visual review. This is a view render, not a screen recording or proof of every menu/assistive-technology behavior.

At [12f8e781](https://github.com/denysshcherbak4/terminal-helper/commit/12f8e78193dcc9a166da32c0c703e36af8f30175), [strict CI](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39042291494) passed 29 PTY cases (one default-filesystem skip), four installer cases, and the dedicated HFSX case on each architecture. Universal compilation, state and actual controller/worker-group lifecycle checks passed. A successful PNG export alone did not prove visual correctness; the exporter now also rejects blank/transparent pixels, and the final PR records the visual inspection of the replacement.

## Published 0.3 verification

Published [0.3.0](https://github.com/denysshcherbak4/terminal-helper/releases/tag/v0.3.0) adds explicit in-place installation. Exact-source [ARM/Intel CI passed](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39164011119) at b322ba2f4c462c7e13bf3ca80a342510591f509c, with 72 installer assertions, 74 update assertions, 8 shell-installer and 8 management cases, 32 PTY cases plus a dedicated case-sensitive fixture, actual Launch Services handoff and three lifecycle paths on each architecture. The main merge tree was identical and its CI also passed. This does not establish a consumer Gatekeeper upgrade.

- `Tests/Updates` compiles with `State.swift`, `Updates.swift` and `UpdateInstaller.swift` and retains the release/network/download/checksum/quarantine boundary checks.
- `Tests/UpdateInstaller` creates signed fixture bundles and a verified fixture DMG. It covers identity/version/signature refusal, supported paths, permissions, owned integration, locks/concurrent edits, atomic bundle exchange, rollback checkpoints, cancellation, quarantine and retained backup. Fixture integration is treated as data, not executed.
- After building, `Tests/UpdateController` receives the built app path, opens a CI-built copy through Launch Services, requests the actual controller to quit and checks process exit and Off. This is an unquarantined fixture, not proof that macOS will approve a downloaded ad-hoc app.
- Native `--termination-self-test` and `--update-cancel-self-test` check external termination and cancellation of update/integration workers. The existing shell, Settings, state, lifecycle and appearance checks remain required.

These commands run only on disposable remote macOS runners with empty user Applications/support fixture paths and no running Terminal Helper instance. The full installer and controller fixtures use the account's actual home; never clear a real installation to satisfy their guards. See [reproducible commands](../README.md#verification-and-development).

Installed users can explicitly run `terminal-helper version`, `terminal-helper check` and `terminal-helper update` without an account or build tools. Version/check/update do not forward arbitrary arguments, and checks/downloads happen only on request. A 0.2 user still needs one manual Finder upgrade to 0.3 before subsequent in-place updates. Public-download trust, per-app opening approval, restart/re-enable and interrupted-update recovery remain separate manual checks; do not substitute fixture counts or historical timing values for them.



## Published 0.3 measured snapshot

GitHub macOS 15.7.9 runners: Apple M1 Virtual / Intel i7-8700B 3.20GHz; zsh 5.9, Swift 6.1.2. Completion fixture: 256 entries, 30 repetitions. Startup: 40 paired fresh-shell trials with identical compinit; no forced cache flush. Idle: 2s settling plus six 1s samples. First observations are not guaranteed cold filesystem measurements; VM scheduling is noisy.

| Measurement | ARM | Intel |
|---|---:|---:|
| Configured first Tab | 36.06 ms | 25.71 ms |
| Warm completion p95 | 10.17 ms | 17.43 ms |
| Unconfigured first-Tab p95 | 332.26 ms | 713.93 ms |
| Paired added startup p95 | 39.31 ms | 28.44 ms |
| Off median RSS | 50672 KiB | 24666 KiB |
| Settled interval CPU | 0.54% | 1.07% |
| Controller / owned children | 1 / 0 | 1 / 0 |

The 30ms added-startup target was missed on ARM and met on Intel this run. The 100ms target was missed for unconfigured first use on both. Negative paired startup medians do not prove a speedup. App logical size: 1,133,599 bytes. Selected ARM-built universal ZIP: 418,290 bytes; DMG: 721,907 bytes. No claim of zero memory/CPU while Off.

## Measurement method

Startup: 40 paired fresh `zsh -d -f -i` subprocesses per condition, with identical `compinit -D`; alternating order reduces systematic cache bias. Report baseline/integrated p95 and p95 of paired added time. First observations are recorded separately; no filesystem cache flush is performed. A supplementary in-process EPOCHREALTIME measurement brackets source alone and excludes compinit and scheduling outside that phase; it does not replace the paired startup measurement.

Completion: actual PTY Tab to a visible useful filename, 256 ordinary fixture files plus the private state directory, 30 repetitions. The warm benchmark initializes completion before timing. A separate benchmark uses 30 fresh shells with no `compinit` setup and includes its first-Tab cost. Do not apply warm results to an unconfigured beginner shell.

Historical snapshot from exact commit 12f8e781, macOS 15.7.9, zsh 5.9, Swift 6.1.2, GitHub-hosted Apple M1 (Virtual) and Intel Core i7-8700B @3.20GHz:

| Measurement | Apple M1 VM | Intel VM |
| --- | ---: | ---: |
| Configured first Tab observation | 15.45 ms | 45.86 ms |
| Configured warm completion p95 | 11.84 ms | 19.61 ms |
| Unconfigured first observation | 182.52 ms | 563.01 ms |
| Unconfigured fresh-shell first Tab p95 | 234.93 ms | 645.82 ms |
| Baseline startup p95 | 176.23 ms | 779.98 ms |
| Integrated startup p95 | 198.40 ms | 652.73 ms |
| Paired added startup p95 | 38.18 ms | 122.66 ms |
| Paired added startup median | 4.48 ms | 3.87 ms |
| Off median RSS | 26,224 KiB | 17,712 KiB |
| Settled interval CPU | 0.935% | 0% at measurement resolution |
| Controller processes / owned children | 1 / 0 | 1 / 0 |
| Logical app bytes | 523,398 | 523,398 |
| Compressed universal app ZIP bytes | 196,095 | 196,095 |

The 30 ms paired-startup and 100 ms unconfigured-first-Tab targets were **not achieved** in this run. Shared-runner wall-clock variance is substantial: the paired median is small and the Intel integrated p95 is lower than baseline, while the paired-difference tail is positive. These measurements do not isolate causality or predict a physical Mac. Secure first-use completion initialization is included in the unconfigured benchmark. No security checks were removed to improve timing. Current exact-run measurements remain available in its JSON artifact; do not silently substitute warm values for first use.

Idle controller: allow a two-second settle, take six one-second RSS/CPU/child-process samples, and calculate CPU consumed over the settled sample interval. OS `ps %CPU` may include process startup; the interval value is the idle measurement. Record logical app bytes, compressed ZIP bytes, hardware, OS, shell, Swift version, and signature status.

Targets: added startup p95 ≤30 ms, first useful suggestion p95 ≤100 ms. Report misses directly. Native/user completion can enumerate large directories or execute trusted completion logic; slow/network filesystems can exceed these targets. Fuzzy enumeration stops after 257 entries, declines above 256 siblings, limits results to 20, and does not recurse.

## Support matrix

| Environment | Evidence and limit |
| --- | --- |
| macOS 15, Apple Silicon and Intel, zsh 5.9 | Automated PTY, native compilation/state/lifecycle, fixture and measurement jobs; exact results in the selected run. |
| macOS 13 minimum | Deployment target and selected API availability; oldest-OS runtime validation remains manual. |
| Terminal.app | Primary intended terminal; PTY testing covers real ZLE; the optional native smoke result is recorded in each run. The full human Terminal.app user flow remains a manual release check. |
| iTerm2 | Not manually validated; no compatibility claim beyond the shared zsh/PTY mechanism. |
| Case-insensitive filesystem | Default runner fixtures. |
| Case-sensitive filesystem | Dedicated runner-owned HFSX fixture; case-sensitive APFS still merits manual testing. |
| Custom ZDOTDIR | Explicit folder selection in Settings, with installer fixture containing spaces. |
| Custom key macros / unsupported syntax | Safe refusal/fallback; no broad shell parser. |
| Missing intermediate path ancestors | Correction is final-component only; leaves unsupported paths intact. |
| Free distribution | Ad-hoc community beta; no Developer ID/notarization. Per-app approval remains a user decision; managed Macs may refuse it. |

## Reviews and release checks

The shell, native app, installer, build/CI, and adjacent callers were read through GitHub APIs by an independent reviewer. Ponytail review and Apple native design guidance were applied. Rendered affordance/typography review uses the actual native PNG.

The formal Codex Security workflow requires a resolved local Git checkout and revision range. That conflicts with the authorized remote-only boundary, so it was not run; independent remote source review is the explicit substitute, not a claimed formal scan.

See [manual verification](MANUAL-VERIFICATION.md) for actual Terminal.app/iTerm2, VoiceOver, appearances, oldest macOS, slow filesystems, install interruption, and release-distribution checks. No public release or personal-Mac installation is implied by a successful CI build.

[Live production CLI installation passed](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39164938119): current updater source built with fixture version 0.1.0 anonymously installed public 0.2.0, with digest/signature, installed quarantine, backup, Off, exact integration and unchanged shell configuration verified. This was current source with an older fixture version, not a historical client. Consumer opening approval remains manual. The smoke-test macOS portability fix is independently reviewed in PR #5.
