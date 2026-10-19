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

Installed users can explicitly run `terminal-helper version`, `terminal-helper check` and `terminal-helper update` without an account or build tools. Version/check/update do not forward arbitrary arguments. In published 0.3.0, checks/downloads happen only on request; 0.3.1 additionally introduces the gated automatic metadata notices described below. A 0.2 user still needs one manual Finder upgrade to 0.3 before subsequent in-place updates. Public-download trust, per-app opening approval, restart/re-enable and interrupted-update recovery remain separate manual checks; do not substitute fixture counts or historical timing values for them.



## Published 0.3.1 notice verification



### Exact-source validation

[ARM/Intel macOS CI passed](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39213307870) at source 1097cf1dd3fd0f1840cbc76ff212751423a9773b. [PR #6](https://github.com/denysshcherbak4/terminal-helper/pull/6) merged as [81dd7fc](https://github.com/denysshcherbak4/terminal-helper/commit/81dd7fc94ed39d149a095207b59a32ad611ffb18), with an identical verified tree.

Each architecture passed 34 persisted-policy assertions, 78 update/transport assertions including real request cancellation, 72 signed bundle/DMG installation assertions, native notice controls including Off/uninstall/stale-callback/skip/manual-override/real-modal fixtures, 8 shell-installer cases, 8 management-command cases, 32 PTY cases plus a dedicated case-sensitive fixture, real Launch Services handoff, state/Settings/lifecycle paths, universal signing and package verification. Lead inspected actual light/dark Settings renders: the checkbox and timing disclosure are readable and not clipped.

Independent remote source/security/ponytail review found no unresolved confirmed finding after fixes. Formal Codex Security scanning requires a local checkout and was not run. Terminal.app AppleEvents/display smoke explicitly skipped. Consumer Gatekeeper approval, real Terminal.app/iTerm2, VoiceOver and oldest macOS 13 remain manual checks. Do not infer those from compilation or fixtures.

### Measurements

macOS 15.7.9, zsh 5.9, Swift 6.1.2; GitHub-hosted Apple M1 Virtual / Intel i7-8700B 3.20GHz. Completion: 256 entries and 30 repetitions. Startup: 40 paired fresh shells with identical compinit; no forced cache flush. Idle: 2s settle and six 1s samples. VM scheduling is noisy; first observations are not guaranteed cold filesystems.

| Measurement | ARM | Intel |
|---|---:|---:|
| Configured first Tab | 42.96 ms | 55.61 ms |
| Warm completion p95 | 7.49 ms | 14.38 ms |
| Unconfigured first-Tab p95 | 504.74 ms | 862.24 ms |
| Paired added-startup p95 | 1.31 ms | 88.51 ms |
| Off median RSS | 50640 KiB | 24672 KiB |
| Settled interval CPU | 0.55% | 0.36% |
| Controller / owned children | 1 / 0 | 1 / 0 |

30ms startup target: ARM met, Intel missed in this run. Unconfigured first-use 100ms target remains missed on both. Negative paired medians do not prove a speedup. App logical size 1245991 bytes; selected universal ZIP 463991 bytes; DMG 769123 bytes. Off remains an idle resident controller, not zero memory/CPU.


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


[Published v0.3.1 production CLI installation passed](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39215155982): current updater source built with VERSION=0.1.0 as an older-version fixture anonymously downloaded and installed public 0.3.1. SHA-256, signature integrity, installed bundle/executable quarantine, retained previous app, Off, exact owned integration and preserved shell configuration passed. This is current source with an older fixture version, not a historical v0.1 binary. Launch Services reopening was requested; consumer Gatekeeper approval remains manual.


## Published 0.3.2 highlighted completion verification

Published [0.3.2](https://github.com/denysshcherbak4/terminal-helper/releases/tag/v0.3.2) uses native menu selection, with reverse highlighting, Up/Down navigation through short and scrolling lists, text-only acceptance and exact Escape cancellation. Protected native keymaps are preserved, including user widgets/macros, and Off is rechecked after native selection returns and before acceptance.

Exact-source [ARM/Intel CI passed](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39228014768) at 563aee498d05b2909e5576ffb30a7f8a7d34501a. Each architecture passed 37 actual PTY cases (one default-filesystem skip covered by dedicated case-sensitive HFSX), 8 shell installer cases, 8 management cases, 78 update assertions, 72 native installer assertions, 34 update-notice policy assertions, native controller/lifecycle tests, universal build/signature and package verification. Terminal.app AppleEvents/display smoke explicitly skipped; consumer terminal, VoiceOver, oldest macOS and opening approval remain manual. Source review found no remaining confirmed issue; the formal local-checkout security scanner was not run. The app includes GPLv3 and historical MIT notices; complete exact-build Corresponding Source is attached to the release.

### Measured snapshot from the exact build
GitHub-hosted macOS 15.7.9, zsh 5.9, Swift 6.1.2; Apple M1 Virtual / Intel i7-8700B 3.20GHz. Completion fixture: 256 entries, 30 repetitions. Startup: 40 paired fresh shells with identical compinit, no forced cache flush. Idle: 2s settling and six 1s samples.

| Measurement | ARM | Intel |
|---|---:|---:|
| Configured first Tab | 18.94 ms | 81.12 ms |
| Warm completion p95 | 21.64 ms | 43.26 ms |
| Unconfigured first-Tab p95 | 230.05 ms | 927.96 ms |
| Paired added-startup p95 | 6.70 ms | 554.42 ms |
| Off median RSS | 50280 KiB | 24748 KiB |
| Settled interval CPU | 0.37% | 1.42% |
| Controller / owned children | 1 / 0 | 1 / 0 |

The 30ms startup target was met on ARM and missed on Intel this run. The 100ms unconfigured-first-use target was missed on both. Shared VM scheduling varies substantially; negative paired medians do not imply speedup, and first observations are not guaranteed cold. Logical app size 1287037 bytes; selected universal ZIP 478280 bytes and DMG 785782 bytes. Off is an idle resident controller, not zero memory/CPU. Raw logs are in the linked CI artifacts.


[Public v0.3.2 production CLI installation passed](https://github.com/denysshcherbak4/terminal-helper/actions/runs/39231135188): current updater source built with VERSION=0.1.0 as an older-version fixture anonymously downloaded and installed public 0.3.2. Digest, signature integrity, bundle/executable quarantine, retained previous app, Off, exact owned integration and preserved shell configuration passed. This is current source with an older fixture version, not a historical v0.1 binary. Launch Services reopening was requested; consumer Gatekeeper approval remains manual.

## Current 0.4.0 development workflow

The exact-source branch adds Python PTY sentinel tests, a 30-request first/warm context benchmark and a recorded mismatch/Insert demonstration. It also compares integrated completion with original configured and unconfigured Tab on the same runner/fixture. All Python executables in these context fixtures are inert sentinels; passing tests establish no probe execution, not real interpreter health.

The current PR records fresh numeric results and run/artifact links separately from the historical tables above. No security checks are bypassed for timing. Unsupported native expansion widgets are declined while On, and Off deliberately preserves original shell behavior. A single owned integration file retains existing installer/updater byte-validation and rollback contracts.
