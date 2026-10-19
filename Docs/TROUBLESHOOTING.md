# Troubleshooting

**There are no suggestions.** Open the menu-bar icon, enable suggestions, install integration in Settings, select the folder containing your .zshrc, and open a new interactive zsh. In the development build, Off delegates the original supported Tab binding instead of generating helper suggestions. The published 0.3.2 version still has inert Tab while Off. Installation status means the file is installed; it cannot prove an already-open shell sourced it.

**My configuration uses ZDOTDIR.** Select that folder in the Settings picker. Select the same folder to uninstall. A Finder-launched app does not assume your shell environment. Do not overwrite or move your entire .zshrc.

**The first Tab is slower.** An unconfigured shell initializes secure zsh completion on first use. Large/remote directories and existing third-party completion functions can take longer. Fuzzy correction only covers a missing final component in a small directory.

**My syntax or keybindings are unusual.** The development build keeps custom correction conservative. While On, unsupported syntax declines known native expansion widgets (including dot-prefixed builtins), because they can execute substitutions before completion. Other captured completion widgets retain their existing user-configured behavior and trust boundary. Off delegates the original supported Tab behavior, including any expansion it already performed. Key macros that cannot be delegated safely stay untouched, and later plugin bindings are never reclaimed automatically. Run terminal-helper doctor in that shell to inspect ownership; adjust plugin loading order only deliberately, or keep the plugin binding.

**Installation or removal is refused.** The scripts reject unsafe symlinks and incomplete/edited managed blocks. Inspect the clearly marked block and the .zshrc.terminal-helper-backup files beside your configuration. Preserve your current file, compare the backup, and rerun the installer to repair a missing owned integration file. Do not replace the whole configuration just to install the app.

**The toggle cannot save state.** The private Terminal Helper folder must belong to your account with mode 700, and its regular state file must have mode 600. The app reports failure and refuses to claim it disabled successfully if it cannot persist Off. Missing or malformed state keeps shell assistance disabled.

**A menu was open when I switched Off.** The next completion/acceptance interaction cancels it. Instant disappearance of every open menu is not promised.

**macOS does not trust the download.** The free beta is ad-hoc signed, without Developer ID/notarization. After attempting to open it, users trusting this exact download may follow [Apple’s per-app process](https://support.apple.com/102445): System Settings → Privacy & Security → Open Anyway. Managed Macs may refuse it. Never override malware/damaged-app warnings, globally disable Gatekeeper or remove quarantine.

**I want to uninstall.** Choose Uninstall shell integration in Settings and the original configuration folder, restart open shells, then delete the app. Missing state keeps any retained widgets disabled. Remove remaining owned support files only after those shells close; keep your backups if you may need them.


**The installer says another operation is in progress.** Install and uninstall serialize edits with a private `.integration-lock` directory. Wait for the operation to finish. A forced kill can leave a stale lock; do not automatically delete it or run two installers. Close Terminal Helper and confirm no installer is running before using `rmdir "$HOME/Library/Application Support/Terminal Helper/.integration-lock"`. This removes only an empty owned lock. If it is nonempty or not yours, stop and inspect it; do not recursively delete the support folder. Then retry installation/repair.

**terminal-helper is not found or the app moved.** Open the current app, install/update/repair integration, then open a new terminal. Existing aliases/functions/commands with this name are deliberately preserved; use the menu instead. Repair after moving the app to refresh its private path.

**Updates say no release is published.** A commit or draft is not a public release. A maintainer must publish a numeric version before it is offered.

**A download fails or its checksum differs.** Retry later and check GitHub connectivity/rate limits. Mismatched, oversized or invalid app bundles are not installed; validation failures leave the previous app untouched. Never bypass the check or run a remote installer script.

**My 0.2 update command still opens a DMG.** That is the old client's behavior. Make one final manual Finder upgrade to published 0.3, open it, repair integration if prompted and restart shells. Subsequent updates from 0.3+ can install in place.

**Automatic installation refuses the location or permissions.** It supports exactly `~/Applications/Terminal Helper.app` or an eligible user-owned `/Applications/Terminal Helper.app`, with a writable app and safe parent. Quit, move the app in Finder to `~/Applications`, reopen and repair integration. Do not use `sudo`, weaken parent permissions or change system-folder ownership to force an update.

**An update refuses integration.** Only exact owned integration data can be refreshed automatically. Preserve edited files and backups. Open the current app and use its explicit Settings repair/update action, restart shells and retry. The automatic updater does not rewrite `.zshrc` or your settings.

**Reopening is blocked or suggestions remain Off after an update.** Launch Services retains macOS opening checks and quarantine. Follow ordinary per-app approval only if you trust the exact download; managed restrictions may still prevent opening. Restart shells, then deliberately enable suggestions. Installation does not enable them automatically.

**An update was interrupted or I need the previous app.** A private `.Terminal-Helper-update-<UUID>` folder beside the app retains `Terminal Helper.app` and `RECOVERY.txt`. Quit the app, open that matching folder in Finder with Go → Go to Folder, and follow its recovery instructions. Handled installation errors roll back the app and owned integration bytes, but an unexpected shutdown is not guaranteed to leave both in the same version. Keep the backup until the new version works. After restoring, repair integration if prompted and restart shells. Do not recursively delete the support directory or bypass macOS security checks.

**No automatic update notice appears (0.3.1).** Confirm suggestions are On and Settings → Check for updates automatically is enabled. A normal launch or a genuine Off→On change checks eligibility; merely leaving the app running does not schedule another check. The 24-hour window starts at the request attempt, including a failed or cancelled request. An exact skipped version is suppressed automatically. Use Check for Updates or `terminal-helper check` at any time for a manual result, including while Off; manual checks ignore the automatic cooldown and skipped version. Public 0.3.0 does not yet have these automatic notices.

**Does Remind Me Later schedule tomorrow's notification?** No. It keeps the version eligible for the next launch/enable event after the attempt's 24-hour window. There is no daily timer or midnight check. Skip This Version suppresses only that version's automatic offer; a future newer version can still appear when eligible.

**I do not want automatic metadata requests.** Disable Check for updates automatically in Settings; the choice is remembered. Suggestions Off also prevents automatic checks and cancels pending ones. This does not disable explicit Check for Updates or `terminal-helper check/update`. Automatic checks fetch metadata only; downloading/installing still requires Update Now or an explicit update command.


**Tab lists matches but arrows do not move a highlight.** Versions through 0.3.1 could start plain completion instead of native menu selection. The 0.3.2 fix starts zsh menu selection explicitly. Use terminal-helper update to install published 0.3.2, restart terminal windows and enable suggestions. A source commit or draft alone does not update an installed app. In a selectable list, arrows move the reverse-highlighted choice; Enter inserts it without executing.


**Doctor reports different versions.** App metadata and the integration already loaded in an open shell are separate facts. Restart that shell after installing/upgrading integration; running a new app cannot replace live widgets inside another process. Doctor only explains problems and never repairs files.
