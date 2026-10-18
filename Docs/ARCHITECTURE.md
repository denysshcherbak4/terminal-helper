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

Unsupported syntax must retain its input. Filenames and descriptions are untrusted terminal content. Test spaces, quotes, Unicode, controls, symlinks, relative paths, tilde, and edits away from the end of the buffer.

Native shell completion does not know Python/Jupyter runtime objects. CSV, Parquet, and notebook suggestions are ordinary files.

## Installation boundary

Installation is an explicit action in Settings, not an app-launch side effect. The bundled installer owns one marked shell configuration block and its integration file. It must preserve unrelated configuration, back up changes, honor ZDOTDIR, and support repeated install/uninstall. App installation on the developer's personal Mac requires separate authorization.

## Distribution boundary

CI runs on GitHub-hosted macOS and uploads a versioned universal test build and checksum. A successful compile or offscreen render does not establish a successful Terminal.app/VoiceOver user flow. The free community beta is ad-hoc signed, without Developer ID/notarization. Apple’s per-app opening approval is a user decision; never globally disable Gatekeeper or strip quarantine.

## Explicit updates

App/Updates.swift performs fixed public-release checks, bounded HTTPS downloads, SHA-256 verification, private saving and quarantine. Only explicit menu/terminal actions make requests. The terminal command delegates to the installed app through private, non-executable app-path metadata, never evaluated or used to forward arbitrary arguments. A verified DMG opens for deliberate Finder replacement; no app self-installation occurs. See UPDATES.md and RELEASING.md.
