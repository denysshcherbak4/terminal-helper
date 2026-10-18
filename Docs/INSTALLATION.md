# Install the free community beta

Download Terminal-Helper-0.2.0-universal.dmg from [GitHub Releases](https://github.com/denysshcherbak4/terminal-helper/releases). Public downloads require no GitHub account or build tools. If it is not published yet, green CI artifacts remain available for review; CI sign-in is required and artifacts expire after 14 days.

1. Open the DMG and drag Terminal Helper to Applications. Use ~/Applications if the system folder is not writable; create it in Finder if needed. No privileged installer or administrator rights are needed by the app/integration.
2. Open it. The free beta is ad-hoc signed, not Developer ID-signed or notarized. Users trusting the exact source may follow [Apple’s per-app process](https://support.apple.com/102445) after the first blocked opening attempt: System Settings → Privacy & Security → Open Anyway → Open. New versions may need approval again.
3. Click >_ → Settings → Install shell integration. Choose Home for ordinary zsh or the directory containing .zshrc if you configured ZDOTDIR.
4. Open a new terminal and enable suggestions. Tab requests, arrows select, Enter accepts text and Escape cancels. A separate Enter executes.

Never override malware/damaged-app warnings, globally disable Gatekeeper, strip quarantine or evade managed restrictions. Ad-hoc signing verifies bundle integrity, not an Apple-verified publisher or malware notarization. Some managed Macs cannot run this beta.

The universal app targets macOS 13+, arm64/x86_64. Runtime CI covers macOS 15 on both architectures; native-terminal/VoiceOver/oldest-system checks remain in [verification](VERIFICATION.md).

## Verify, update and remove

Checksums in SHA256SUMS.txt and the per-DMG .sha256 file verify matching bytes, not publisher identity. From the folder containing the named DMG and checksum, optional native verification is shasum -a 256 -c Terminal-Helper-0.2.0-universal.dmg.sha256.

Check for Updates or terminal-helper update verifies and opens a new DMG. Then Disable and Quit, replace in Finder, reopen, update integration if prompted and restart shells. See [updates](UPDATES.md).

Off prevents automatic assistance work; the controller stays resident. Explicit installation/removal and requested updates remain available. Uninstall integration using the original configuration folder, restart shells and delete the app. Backups remain yours. Delete update download folders separately. See [troubleshooting](TROUBLESHOOTING.md) for partial/refused installation.
