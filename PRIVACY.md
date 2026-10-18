# Privacy

Terminal Helper has no accounts, telemetry, analytics, crash uploads or cloud AI. It does not collect or transmit terminal history, command buffers, environment contents, private filenames, configuration or filesystem contents.

## Local suggestions and settings

Completion examines the context and nearby entries locally when enabled and requested. It does not index the disk. Existing third-party completion code retains its own trust boundary, including any independent networking.

Private On/Off state and integration live under ~/Library/Application Support/Terminal Helper. The non-executable mode-0600 app-path record stores the app bundle's absolute location for explicit terminal management commands; it is never evaluated as shell code or transmitted. A transient owned lock serializes installation/removal.

The local preference ShellConfigurationDirectory (domain io.github.denysshcherbak4.terminal-helper) remembers the successful configuration-folder selection. Integration uninstall clears it. Configuration backups beside .zshrc contain the previous file and stay on your device.

## Updates are explicit

There is no startup request, periodic checker, telemetry beacon or automatic download. Check for Updates and terminal-helper check/update contact GitHub's public release API. A requested download contacts this repository's HTTPS GitHub Release assets and GitHub's asset CDN. Requests use a generic Terminal Helper user agent, without an account, credentials or device identifier. GitHub/CDN sees ordinary metadata including IP address; its policies apply.

The installed version is compared locally and is not included in the request. Only published release metadata and requested archives/checksums are fetched. Suggestions Off prevents automatic assistance work; it does not block an update action you explicitly request.

Verified DMGs are saved in a new private `Downloads/Terminal Helper <version> <UUID>` folder, retaining macOS quarantine. Delete them after installing if desired.

From 0.3, an explicit installation request can validate and install the app at a supported writable Applications location, refresh exact owned integration data and reopen through macOS Launch Services. This is not a background installation and does not rewrite `.zshrc` or change settings. The controller saves Off before quitting; restart shells and enable suggestions deliberately afterward.

A private `.Terminal-Helper-update-<UUID>` folder beside the app retains the previous app and `RECOVERY.txt`. It contains local app/recovery data, not terminal history. Delete it only after confirming the new version works. App and integration are not a guaranteed combined transaction across a crash or power loss. A 0.2 client still needs manual Finder replacement for its final upgrade to 0.3.

## Permissions and removal

No global keyboard-monitoring, Accessibility, Screen Recording or password-interception permission is requested. A folder picker and Apple's per-app opening approval are explicit user actions.

Uninstall removes the owned block, integration, state and app-path marker, preserving unrelated configuration and backups. Restart shells before deleting the app or remaining owned support files. Delete saved download folders and retained app-backup folders separately. There is no Terminal Helper cloud account or server data to erase.

GitHub hosting/downloads, Apple operating-system security checks and optional reports are separate services. Send only synthetic, redacted reproductions in reports.
