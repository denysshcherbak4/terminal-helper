# Installation

## Current download status

This is an engineering preview. The DMG is a complete universal macOS app package, but its signature is ad-hoc and it has not been notarized. Ordinary users should wait for a Developer ID-signed, notarized public release. If macOS rejects a preview download, stop; do not disable Gatekeeper, remove quarantine attributes or run a remote installation command.

[Public releases](https://github.com/denysshcherbak4/terminal-helper/releases) appear only after maintainer approval. Draft releases are visible only to authorized repository collaborators.

## Download a test package

Open [CI builds on main](https://github.com/denysshcherbak4/terminal-helper/actions/workflows/macos.yml?query=branch%3Amain), choose a successful run and download its Terminal-Helper artifact. GitHub currently requires sign-in. Unzip it; dist/ contains a versioned universal DMG, an app ZIP and SHA256SUMS.txt. Artifacts expire after 14 days.

Optional integrity verification from that dist folder:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

This checks file integrity, not a trusted developer identity.

## Copy and set up the app

1. Open the DMG and drag Terminal Helper to Applications. Eject the image. The app does not install a daemon or require an administrator password.
2. Open a trusted build from Applications. Use the >_ icon at the top of the screen and open Settings.
3. Choose Install shell integration. For a normal setup use your home folder; for a custom ZDOTDIR select the folder containing that .zshrc. The installer backs up the existing file and adds only its marked block.
4. Open a new terminal window, then turn Enable suggestions On.
5. Press Tab for suggestions, arrows to select, Enter to accept text and Escape to cancel. Execute the completed command with a separate Enter after the menu closes.

No Xcode, Python, Node or source build is needed for the installed app. It targets macOS 13+, Apple Silicon and Intel. Terminal.app is the primary intended terminal; exact tested support and manual limits are in [verification](VERIFICATION.md).

## Off and removal

Off stops Terminal Helper generation and scans; the controller stays resident. Already-open shells check at the next completion/acceptance interaction. Disable and Quit persists Off and terminates owned installer workers.

To remove integration, use Settings → Uninstall shell integration and the same configuration folder. Restart open shells, then delete the app. Backups remain yours. Partial/edited blocks, unsafe symlinks or concurrent changes are refused; see [troubleshooting](TROUBLESHOOTING.md).

## Maintainer distribution gate

No Developer ID/notarization credentials are currently configured in GitHub. Before public publication, sign with a Developer ID Application identity and hardened runtime, notarize using Apple's supported notarytool workflow, staple the ticket, and verify the downloaded DMG/app with Gatekeeper on a fresh authorized test Mac. Never publish an ad-hoc preview as a trusted release. See [Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
