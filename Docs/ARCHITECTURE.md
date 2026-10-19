# Architecture and safety contract

Terminal Helper assists an existing interactive zsh. It is not a terminal emulator or language runtime.

## Ownership

- A native AppKit menu-bar controller owns user-visible state and explicit integration installation.
- A sourced zsh integration owns completion interaction inside each integrated shell. There is no always-running helper daemon, global keyboard hook, network service, account, telemetry, history store, or database.
- The user's existing completion definitions remain executable shell code within their existing trust boundary. Do not source completion files from an untrusted project or disable zsh completion security checks.

## State v1

The controller atomically writes a user-owned, regular mode-0600 file at `~/Library/Application Support/Terminal Helper/state` inside a private mode-0700 directory. Exact bytes `terminal-helper-v1:on\n` enable assistance. Off is `terminal-helper-v1:off\n`. Missing, malformed, unsafe, or unreadable state disables assistance. The state is data and is never sourced.

The shell checks state at user interaction boundaries, including acceptance. There is no polling or process per keystroke. Multiple integrated shells share this switch. A menu already on screen may remain visible until the next interaction; instant dismissal is not promised.

Off prevents Terminal Helper from generating candidates or scanning directories. The controller remains resident and consumes memory. Disable and Quit must persist Off before exiting. A controller crash is not the same operation as Disable and Quit: a previously enabled state may remain until the app writes Off.

## Completion

Use ZLE and zsh completion infrastructure rather than evaluating a typed command or building a shell parser. Completion edits the buffer; it never executes the accepted command. Ordinary command execution is a separate user action. Existing valid paths must not be replaced by fuzzy alternatives. Exact/prefix results precede corrections, with clear labels.

Custom correction retains conservative syntax checks. While On, unsupported syntax declines known native expansion widgets (including dot-prefixed builtins), because they can execute substitutions before completion. Other captured completion widgets retain their existing user-configured behavior and trust boundary. Off delegates the original supported Tab behavior, including any expansion it already performed. The helper does not evaluate the buffer. Filenames and descriptions are untrusted terminal content. Test spaces, quotes, Unicode, controls, symlinks, relative paths, tilde, and edits away from the end of the buffer.

Native shell completion does not know Python/Jupyter runtime objects. CSV, Parquet, and notebook suggestions are ordinary files.

## Installation boundary

Installation is an explicit action in Settings, not an app-launch side effect. The bundled installer owns one marked shell configuration block and its integration file. It must preserve unrelated configuration, back up changes, honor ZDOTDIR, and support repeated install/uninstall. App installation on the developer's personal Mac requires separate authorization.

## Distribution boundary

CI runs on GitHub-hosted macOS and uploads a versioned universal test build and checksum. A successful compile or offscreen render does not establish a successful Terminal.app/VoiceOver user flow. The free community beta is ad-hoc signed, without Developer ID/notarization. Apple’s per-app opening approval is a user decision; never globally disable Gatekeeper or strip quarantine.

## Update checks and explicit installation

`App/Updates.swift` performs fixed public-release checks, bounded HTTPS downloads, SHA-256 verification, private saving and quarantine. From 0.3.1, eligible automatic metadata checks can also make requests; checksum/DMG download and installation remain explicit. The terminal command delegates fixed subcommands through private, non-executable `app-path` metadata, never evaluated or used to forward arbitrary arguments.

Version 0.2 verifies and opens a DMG for Finder replacement. The 0.3 installer validates the staged app's expected bundle identity, release version and signature integrity. It installs only at the canonical home Applications path or an eligible user-owned system Applications path, without elevation or a fallback destination.

After validation, the GUI is requested to persist Off and quit. Atomic bundle exchange keeps the target occupied and retains the old app in a private sibling `.Terminal-Helper-update-<UUID>` folder with `RECOVERY.txt`. Existing integration data is upgraded only when exact and owned; `.zshrc` and settings are not rewritten. Handled errors swap the app back and restore prior integration bytes. The app and integration do not form a guaranteed transaction across a crash or power loss; backups and startup mismatch checks support recovery.

After integration refresh, the installed app reopens through Launch Services and remains Off. Existing shells must restart before enabling suggestions. Quarantine and macOS opening checks remain effective; an ad-hoc signature establishes integrity, not Apple-verified publisher identity or notarization. Normal launch can trigger the gated 0.3.1 metadata-only check described below; there is no persistent daily timer or unattended download/installation.

See [updates](UPDATES.md) and [release procedure](RELEASING.md). A 0.2 user must manually install 0.3 once before subsequent automatic updates are available.

## Automatic notice policy in 0.3.1

`App/UpdateNotices.swift` keeps a default-enabled automatic-check preference, last attempt date and exact skipped version in local UserDefaults. The controller gates normal launch and genuine Off→On events on both suggestions On and that preference. It records a started attempt before the request. A 24-hour cooldown includes failed/cancelled attempts; clock rollback resets eligibility. No recurring timer or helper daemon schedules checks while the app merely remains running.

The request reuses bounded public-release metadata validation. Off cancels it, and late callbacks must not show an offer. Update Now explicitly starts the existing verified installer, Remind Me Later leaves the attempt cooldown intact, and Skip This Version suppresses only the exact automatic version. Manual checks/updates remain available while Off and bypass the policy's cooldown/skipped version. Automatic checking never requests checksums or app assets. No preference/date/version record or terminal data is transmitted.

## Binding fallback and doctor (development build)

The integration captures supported widget bindings per emacs/viins map once. While On, unsupported syntax declines known native expansion widgets (including dot-prefixed builtins), because they can execute substitutions before completion. Other captured completion widgets retain their existing user-configured behavior and trust boundary. Off delegates the original supported Tab behavior, including any expansion it already performed. Unsafe macros stay untouched; later plugin bindings remain authoritative. Enable/disable changes shared state, not the wrapper stack. A native menu may remain until it closes, with state rechecked before accepting helper text. No polling or per-keystroke process is added.

terminal-helper doctor collects this shell's loaded integration, current keymap and binding ownership in-process, separately from the app's version metadata. It reports missing/unsafe state and conflicts with reversible next steps, never repairs automatically or emits private input/history/environment values.

## Explicit Python context (development preview)

The same owned integration file implements an explicit Ctrl-X Ctrl-P widget; no new app worker, network service or installation path is added. It registers only an available sequence in emacs/viins, checking parent and longer sequences too. Doctor reads live ownership without repairing it.

A bounded inspector recognizes simple pip/python -m pip install forms and current-directory .venv metadata. It uses native zsh modules and command resolution, never executable probes. It preserves raw arguments, declines ambiguity, and quotes the proposed absolute interpreter path. A temporary copied keymap provides Enter: Insert text and Escape: Dismiss without replacing user-map bindings. Editing dismisses; insertion rechecks On and metadata/resolution identity. Evidence is neither runtime validation nor a package-destination guarantee. See [the supported subset](PYTHON-ASSISTANCE.md).
