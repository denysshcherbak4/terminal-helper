# Privacy

Terminal Helper has no accounts, telemetry, analytics, crash-upload service, cloud AI or network client. It does not collect or transmit terminal history, command buffers, environment contents, filenames or filesystem contents.

The menu-bar controller reads/writes its private On/Off state, reports whether its integration file exists, and changes shell configuration only during an explicit install/uninstall action. The zsh integration examines the current completion context and nearby filesystem entries locally when enabled and completion is requested. It does not index the whole disk.

Local app-owned data lives in `~/Library/Application Support/Terminal Helper`: the integration, private state and transient installation lock. Installation backs up the selected .zshrc next to that file before editing its marked block. Backups contain the original configuration and stay on your device.

Existing zsh history behavior and third-party completion definitions are controlled by your shell configuration. Such definitions can execute code or access the network independently of Terminal Helper; install only ones you trust.

The app requests no global keyboard-monitoring, Accessibility, Screen Recording or password-interception permission. Opening a configuration-folder picker is an explicit file-selection action.

Uninstall removes the owned block, integration and state, preserving unrelated configuration and backups. Close/restart integrated shells before deleting any remaining owned support directory. No remote account or server data needs deletion.

Repository hosting, CI downloads, signing/notarization and optional bug/security reports are separate GitHub/Apple services, governed by their policies. Send only synthetic, redacted reproductions when reporting a problem.
