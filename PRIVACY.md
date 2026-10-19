# Privacy

Terminal Helper has no accounts, telemetry, analytics, crash uploads or cloud AI. It does not collect or transmit terminal history, command buffers, environment contents, private filenames, configuration or filesystem contents.

## Local suggestions and settings

Terminal Helper completion examines context and nearby entries locally when enabled and requested. It does not index the disk. In this development build, Off and unsupported syntax delegate to the original supported Tab widget; that ordinary completion or third-party plugin may independently scan files or use networking. It remains within its existing trust boundary and is not Terminal Helper assistance. Key macros that cannot be safely delegated stay untouched.

Private On/Off state and integration live under ~/Library/Application Support/Terminal Helper. The non-executable mode-0600 app-path record stores the app bundle's absolute location for explicit terminal management commands; it is never evaluated as shell code or transmitted. A transient owned lock serializes installation/removal.

The local preference ShellConfigurationDirectory (domain io.github.denysshcherbak4.terminal-helper) remembers the successful configuration-folder selection. Integration uninstall clears it. Configuration backups beside .zshrc contain the previous file and stay on your device.

Automatic-notice preferences are local UserDefaults data: `AutomaticUpdateChecksEnabled` (default true when absent), `AutomaticUpdateLastAttempt` (request-attempt date), and `AutomaticUpdateSkippedVersion` (one exact version). Turning the setting off is preserved. These records contain no history, command buffers or environment data and are not sent to GitHub.

## Update notices and explicit installation

In 0.3.0, checks are manual. Version 0.3.1 can request GitHub's public release metadata at a normal app launch or a real change from suggestions Off to On, only when suggestions are On and **Check for updates automatically** is enabled. A 24-hour attempt cooldown applies; failed or cancelled attempts count. There is no persistent daily timer, daemon or telemetry beacon, so a continuously running On app checks again only at a later eligible launch/enable event. Clock rollback can reset eligibility rather than blocking it indefinitely.

Off cancels pending automatic checks and suppresses late offers. Disabling the checkbox prevents automatic checking without requiring suggestions to be disabled. Manual Check for Updates and terminal-helper check/update remain available while Off and ignore the automatic cooldown/skipped version. Automatic requests fetch catalog metadata only, never the checksum, DMG or app. **Update Now** or an existing explicit update action is required before download/install. A requested download contacts this repository's HTTPS GitHub Release assets and GitHub's asset CDN. Requests use a generic Terminal Helper user agent, without an account, credentials or device identifier. GitHub/CDN sees ordinary metadata including IP address; its policies apply.

The installed version is compared locally and is not included in the request. Only published release metadata and requested archives/checksums are fetched. Suggestions Off prevents automatic assistance and automatic update-notice requests; it does not block an update action you explicitly request. Remind Me Later waits for the next eligible event; Skip This Version records only the exact automatic offer, and does not suppress manual checks or future versions.

Verified DMGs are saved in a new private `Downloads/Terminal Helper <version> <UUID>` folder, retaining macOS quarantine. Delete them after installing if desired.

From 0.3, an explicit installation request can validate and install the app at a supported writable Applications location, refresh exact owned integration data and reopen through macOS Launch Services. This is not a background installation and does not rewrite `.zshrc` or change settings. The controller saves Off before quitting; restart shells and enable suggestions deliberately afterward.

A private `.Terminal-Helper-update-<UUID>` folder beside the app retains the previous app and `RECOVERY.txt`. It contains local app/recovery data, not terminal history. Delete it only after confirming the new version works. App and integration are not a guaranteed combined transaction across a crash or power loss. A 0.2 client still needs manual Finder replacement for its final upgrade to 0.3.

## Permissions and removal

No global keyboard-monitoring, Accessibility, Screen Recording or password-interception permission is requested. A folder picker and Apple's per-app opening approval are explicit user actions.

Uninstall removes the owned block, integration, state and app-path marker, preserving unrelated configuration and backups. Restart shells before deleting the app or remaining owned support files. Delete saved download folders and retained app-backup folders separately. Removing integration does not reset the automatic-check preference or its local attempt/skip records. These app preferences may remain after the app is deleted; they stay on your device. There is no Terminal Helper cloud account or server data to erase.

GitHub hosting/downloads, Apple operating-system security checks and optional reports are separate services. Send only synthetic, redacted reproductions in reports.

## Explicit shell diagnostics (development build)

terminal-helper doctor runs in the shell where you invoke it. It reads bounded owned state/app metadata and current keybinding ownership to distinguish installation from a loaded integration. It does not repair configuration, inspect history, print command buffers or macro payloads, or dump environment values. App metadata cannot prove which code an already-open shell loaded. No diagnostic information is uploaded.
