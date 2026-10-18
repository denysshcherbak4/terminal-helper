# Troubleshooting

**There are no suggestions.** Open the menu-bar icon, enable suggestions, install integration in Settings, select the folder containing your .zshrc, and open a new interactive zsh. Tab is intentionally inert while Terminal Helper is Off. Installation status means the file is installed; it cannot prove an already-open shell sourced it.

**My configuration uses ZDOTDIR.** Select that folder in the Settings picker. Select the same folder to uninstall. A Finder-launched app does not assume your shell environment. Do not overwrite or move your entire .zshrc.

**The first Tab is slower.** An unconfigured shell initializes secure zsh completion on first use. Large/remote directories and existing third-party completion functions can take longer. Fuzzy correction only covers a missing final component in a small directory.

**My syntax or keybindings are unusual.** Expressions, multiline input, key macros, and ambiguous syntax may be refused safely. Keep the input and use your existing shell workflow. Terminal Helper owns Tab while installed; uninstall and restart shells to restore the original startup configuration.

**Installation or removal is refused.** The scripts reject unsafe symlinks and incomplete/edited managed blocks. Inspect the clearly marked block and the .zshrc.terminal-helper-backup files beside your configuration. Preserve your current file, compare the backup, and rerun the installer to repair a missing owned integration file. Do not replace the whole configuration just to install the app.

**The toggle cannot save state.** The private Terminal Helper folder must belong to your account with mode 700, and its regular state file must have mode 600. The app reports failure and refuses to claim it disabled successfully if it cannot persist Off. Missing or malformed state keeps shell assistance disabled.

**A menu was open when I switched Off.** The next completion/acceptance interaction cancels it. Instant disappearance of every open menu is not promised.

**macOS does not trust the download.** The free beta is ad-hoc signed, without Developer ID/notarization. After attempting to open it, users trusting this exact download may follow [Apple’s per-app process](https://support.apple.com/102445): System Settings → Privacy & Security → Open Anyway. Managed Macs may refuse it. Never override malware/damaged-app warnings, globally disable Gatekeeper or remove quarantine.

**I want to uninstall.** Choose Uninstall shell integration in Settings and the original configuration folder, restart open shells, then delete the app. Missing state keeps any retained widgets disabled. Remove remaining owned support files only after those shells close; keep your backups if you may need them.


**The installer says another operation is in progress.** Install and uninstall serialize edits with a private `.integration-lock` directory. Wait for the operation to finish. A forced kill can leave a stale lock; do not automatically delete it or run two installers. Close Terminal Helper and confirm no installer is running before using `rmdir "$HOME/Library/Application Support/Terminal Helper/.integration-lock"`. This removes only an empty owned lock. If it is nonempty or not yours, stop and inspect it; do not recursively delete the support folder. Then retry installation/repair.

**terminal-helper is not found or the app moved.** Open the current app, install/update/repair integration, then open a new terminal. Existing aliases/functions/commands with this name are deliberately preserved; use the menu instead. Repair after moving the app to refresh its private path.

**Updates say no release is published.** A commit or draft is not a public release. A maintainer must publish a numeric version before it is offered.

**A download fails or its checksum differs.** Retry later and check GitHub connectivity/rate limits. Mismatched or oversized responses are not opened; the previous app remains untouched. Never bypass the check or run a remote installer script.
