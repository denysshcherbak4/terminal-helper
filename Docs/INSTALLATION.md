# Install the free community beta

Download the latest published universal DMG from [GitHub Releases](https://github.com/denysshcherbak4/terminal-helper/releases). Public downloads require no GitHub account or build tools. Version 0.3.0 adds subsequent in-place updates; until it is published, the README's public download remains 0.2.0. Green CI artifacts are for review, require GitHub sign-in and expire after 14 days.

1. Open the DMG and drag Terminal Helper to **Applications inside your home folder** (`~/Applications`); create it in Finder if needed. This is recommended for installation and updates without administrator rights. `/Applications` also works when your account owns and can write this app.
2. Open it. The free beta is ad-hoc signed, not Developer ID-signed or notarized. Users trusting the exact source may follow [Apple’s per-app process](https://support.apple.com/102445) after the first blocked opening attempt: System Settings → Privacy & Security → Open Anyway → Open. New versions may need approval again.
3. Click >_ → Settings → Install shell integration. Choose Home for ordinary zsh or the directory containing .zshrc if you configured ZDOTDIR.
4. Open a new terminal and enable suggestions. Tab requests, arrows select, Enter accepts text and Escape cancels. A separate Enter executes.

Never override malware/damaged-app warnings, globally disable Gatekeeper, strip quarantine or evade managed restrictions. Ad-hoc signing verifies bundle integrity, not an Apple-verified publisher or malware notarization. Some managed Macs cannot run this beta.

The universal app targets macOS 13+, arm64/x86_64. Runtime CI covers macOS 15 on both architectures; native-terminal/VoiceOver/oldest-system checks remain in [verification](VERIFICATION.md).

## Verify, update and remove

Checksums in SHA256SUMS.txt and the per-DMG .sha256 file verify matching bytes, not publisher identity. From the folder containing the named DMG and checksum, optional native verification is shasum -a 256 -c Terminal-Helper-0.2.0-universal.dmg.sha256.

**Already using 0.2?** Make one final manual upgrade to 0.3 when it is published: the old command opens the verified DMG, then Disable and Quit, replace in Finder, reopen, repair integration if prompted and restart shells. An old executable cannot perform the new installation flow.

**Using 0.3 or later?** Check for Updates and explicitly choose installation, or run `terminal-helper update`. Subsequent updates verify and replace the app, retain a recovery backup and reopen through macOS. They do not rewrite `.zshrc` or settings. Suggestions stay Off; restart shells before enabling them. A supported writable Applications location is required. See [updates](UPDATES.md).

Off prevents automatic assistance work; the controller stays resident. Explicit installation/removal and requested updates remain available. Uninstall integration using the original configuration folder, restart shells and delete the app. Backups remain yours. Delete downloaded DMGs and retained `.Terminal-Helper-update-<UUID>` app-backup folders separately after confirming you no longer need them. See [troubleshooting](TROUBLESHOOTING.md) for partial/refused installation.
