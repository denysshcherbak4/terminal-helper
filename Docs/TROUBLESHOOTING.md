# Troubleshooting

**There are no suggestions.** Open the menu-bar icon, enable suggestions, install integration in Settings, select the folder containing your .zshrc, and open a new interactive zsh. Tab is intentionally inert while Terminal Helper is Off. Installation status means the file is installed; it cannot prove an already-open shell sourced it.

**My configuration uses ZDOTDIR.** Select that folder in the Settings picker. Select the same folder to uninstall. A Finder-launched app does not assume your shell environment. Do not overwrite or move your entire .zshrc.

**The first Tab is slower.** An unconfigured shell initializes secure zsh completion on first use. Large/remote directories and existing third-party completion functions can take longer. Fuzzy correction only covers a missing final component in a small directory.

**My syntax or keybindings are unusual.** Expressions, multiline input, key macros, and ambiguous syntax may be refused safely. Keep the input and use your existing shell workflow. Terminal Helper owns Tab while installed; uninstall and restart shells to restore the original startup configuration.

**Installation or removal is refused.** The scripts reject unsafe symlinks and incomplete/edited managed blocks. Inspect the clearly marked block and the .zshrc.terminal-helper-backup files beside your configuration. Preserve your current file, compare the backup, and rerun the installer to repair a missing owned integration file. Do not replace the whole configuration just to install the app.

**The toggle cannot save state.** The private Terminal Helper folder must belong to your account with mode 700, and its regular state file must have mode 600. The app reports failure and refuses to claim it disabled successfully if it cannot persist Off. Missing or malformed state keeps shell assistance disabled.

**A menu was open when I switched Off.** The next completion/acceptance interaction cancels it. Instant disappearance of every open menu is not promised.

**macOS does not trust the download.** The current engineering artifact has ad-hoc signing, no Developer ID identity and no notarization. Do not disable Gatekeeper. A signed and notarized build is needed for the intended normal public installation flow.

**I want to uninstall.** Choose Uninstall shell integration in Settings and the original configuration folder, restart open shells, then delete the app. Missing state keeps any retained widgets disabled. Remove remaining owned support files only after those shells close; keep your backups if you may need them.
