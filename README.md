# Terminal Helper

**Helpful terminal suggestions, with one switch to turn them off.**

## Install on macOS

**macOS 13+ · Apple Silicon and Intel · no Xcode, Python, or Node needed**

**Current availability: engineering preview.** The test app is ad-hoc signed and is **not notarized**. A normal, Gatekeeper-trusted public download is not available yet. If macOS refuses the preview, stop; do not disable Gatekeeper or remove quarantine protection.

[**Download a test build →**](https://github.com/denysshcherbak4/terminal-helper/actions/workflows/macos.yml?query=branch%3Amain) · [Public releases](https://github.com/denysshcherbak4/terminal-helper/releases) · [Installation help](Docs/INSTALLATION.md)

1. Open the test-build link, select a **green run on main**, and download its `Terminal-Helper-macos-15-…` artifact under **Artifacts**. GitHub currently requires sign-in for these CI downloads.
2. Unzip the download. In `dist`, find the versioned **universal .dmg** and `SHA256SUMS.txt`. Both architectures use the same installation steps.
3. Open the DMG and drag **Terminal Helper** to **Applications**. No privileged installer or shell command is required to copy the app.
4. With a trusted build, open Terminal Helper from Applications. Click its **>_ menu-bar icon → Settings → Install shell integration**. Use your home folder, or choose your custom `ZDOTDIR`.
5. Open a **new terminal window**, then switch **Enable suggestions** On. Tab requests completion; arrows select; Enter accepts text; Escape cancels. Press Enter separately to execute.

Developer ID signing, notarization and a public release are the remaining distribution gates. The prepared preview is for technical review; [verification](Docs/VERIFICATION.md) records what is tested. The installed app needs no account and makes no network requests.

## What it does

Terminal Helper is a native macOS menu-bar app for the interactive zsh you already use. Terminal.app is the primary target; real terminal-app and assistive-technology checks are listed in the [manual checklist](Docs/MANUAL-VERIFICATION.md).

- Complete actual files, directories and executable names.
- Reuse existing command-specific completion, including Git where configured.
- Offer labelled, one-edit corrections for a missing final path component. Exact/prefix matches come first; existing valid paths are never replaced with fuzzy alternatives.
- Show reliable descriptions supplied by configured completion definitions.
- Complete CSV, Parquet and notebook filenames as ordinary files. It does not inspect Python or Jupyter objects.

Accepting a result edits the buffer and never executes it. Unsupported expressions and ambiguous syntax retain the input. Corrections do not search recursively and decline above 256 sibling entries; at most 20 corrections are offered. Existing native/third-party completion can still be expensive in large or remote directories.

## One switch

**On:** assistance is available in integrated interactive shells.

**Off:** While idle, Terminal Helper generates no suggestions, scans no directories, starts no helper processes and performs no polling or network requests. Its Tab binding is intentionally inert. Explicit installation/removal may run a short-lived owned worker. The idle menu-bar controller stays resident and uses memory.

**Disable and Quit:** save Off, terminate any owned installer workers, and exit. Existing shells recheck state on the next completion/acceptance interaction. A pending menu may remain visible until then. Missing or malformed state disables assistance; an unexpected controller crash may leave the last enabled state.

## Remove it

In Settings choose **Uninstall shell integration**, using the same configuration folder selected during installation. Restart open shells, then move the app to Trash. The narrow managed block and owned integration/state files are removed; unrelated configuration and uniquely named backups are preserved.

Install/repair and uninstall are repeatable, make backups before configuration edits, and refuse unsafe or changed targets. They serialize concurrent operations. A busy/stale lock is refused rather than stolen; see [recovery](Docs/TROUBLESHOOTING.md).

## Privacy and security

No telemetry, command/history collection, environment dumps, account, cloud AI, database, whole-disk index, global keyboard monitor, Accessibility permission, or screen recording.

The app and integration run with your ordinary user privileges. Existing third-party zsh completion is executable code and retains its own trust boundary; use trusted completion definitions. No typed command is evaluated to produce suggestions.

Read the [privacy policy](PRIVACY.md) and [security policy](SECURITY.md). Report vulnerabilities **privately** through [GitHub security reporting](https://github.com/denysshcherbak4/terminal-helper/security/advisories/new), not public issues. GitHub secret scanning and push protection are enabled.

## Verification and development

[CI and measurements](Docs/VERIFICATION.md) · [Architecture](Docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md) · [Roadmap](Docs/ROADMAP.md)

The current engineering targets are added startup p95 ≤30 ms and first useful suggestion p95 ≤100 ms on a documented fixture. Historical runs missed startup and unconfigured-first-Tab targets; warm values must not be substituted for first-use values. Every artifact contains the exact commit, environment, raw measurements and test logs.

Build only on a disposable macOS development machine or remote runner with Xcode command-line tools; Python 3 is for tests:

```sh
bash Scripts/build.sh
python3 Tests/Shell/test_pty.py
python3 Tests/Shell/test_install.py
"dist/Terminal Helper.app/Contents/MacOS/TerminalHelper" --self-test
"dist/Terminal Helper.app/Contents/MacOS/TerminalHelper" --lifecycle-test
python3 Tests/Performance/measure.py
bash Scripts/package.sh
```

Builds target macOS 13 and contain arm64/x86_64. The native icon is generated from editable [vector sources](Assets). CI artifacts expire after 14 days; a draft release is not a public download.

## License

[MIT](LICENSE). Copyright 2026 denysshcherbak4 and contributors. See the license for terms and warranty disclaimer.
