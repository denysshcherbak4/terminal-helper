# Terminal Helper

**Helpful terminal suggestions, with one switch to turn them off.**

A small native macOS menu-bar app controlling an interactive zsh integration. Terminal.app is the primary manual-validation target. It assists the terminal you already use.

## Test build status

This is an engineering preview, not a public release. The repository name remains `terminal-helper`. CI builds a universal Apple Silicon/Intel app targeting **macOS 13 or later**. Build results and actual measurements are recorded in [verification](Docs/VERIFICATION.md).

No Developer ID signing/notarization credentials are configured. CI performs ad-hoc integrity signing; this does **not** make a downloaded build trusted by Gatekeeper. Do not disable Gatekeeper. A normal beginner-friendly public installation remains blocked until Developer ID signing and notarization are configured and tested.

## Try the CI artifact

1. Open the successful [macOS MVP Actions run](https://github.com/denysshcherbak4/terminal-helper/actions/workflows/macos.yml) for the PR's exact commit. GitHub login may be required to download artifacts.
2. Download `Terminal-Helper-macos-15-<commit>` or its Intel-runner equivalent. Both builds contain a universal app, a versioned ZIP, `SHA256SUMS.txt`, test logs, a real Settings render, and measurement results.
3. Verify the versioned ZIP against its checksum. Unzip to obtain `Terminal Helper.app`. Installing/running on your own Mac is a separate, explicitly authorized testing step. The unsigned-developer-identity limitation above applies.
4. Once a trusted build is available, drag it to Applications and open it. Use the terminal prompt icon in the macOS menu bar → Settings → Install or repair shell integration. Open a new interactive zsh.
5. Toggle **Enable suggestions**. Tab requests completion, arrows navigate, Enter accepts text, and Escape restores the original input. Execution requires a separate Enter after acceptance.

No Xcode, Python, Node, account, cloud AI, screen recording, Accessibility permission, or whole-disk index is needed by the installed app. Developers need Xcode command-line tools to build; CI tests use Python.

## What it does

- Real file/directory and executable completion through zsh's completion system.
- Existing command-specific completion, including Git where configured.
- Explicitly labelled typo correction of a missing final path component, using nearby existing entries. Missing intermediate ancestors fall back unchanged.
- Filenames such as CSV, Parquet, and notebooks are ordinary files. There is no Python/Jupyter runtime introspection.
- Existing zsh completion descriptions where provided by configured definitions.
- Native On/Off status, integration status, Settings, Help, and Disable and Quit.

Exact/prefix results take priority. A valid path is never replaced with a fuzzy alternative. Unsupported syntax is kept intact. Existing third-party completion definitions execute with your shell's normal user privileges; use only trusted definitions.

## On, Off, and Quit

On allows assistance in integrated interactive shells. Off prevents Terminal Helper candidate generation and filesystem scans; its Tab binding is intentionally inert while Off. The idle controller remains resident and consumes memory. Original keybindings are restored in new shells after uninstall.

The shared switch is checked at completion and acceptance boundaries, including in already-open shells. A pending menu can remain visible until interaction; instant dismissal is not promised. Disable and Quit writes Off before exiting. Missing/malformed state fails closed. An unexpected controller crash may leave the last enabled state, unlike Disable and Quit.

## Shell configuration and uninstall

Install/repair adds one clearly marked block to `.zshrc` and copies the bundled integration to the private `~/Library/Application Support/Terminal Helper` directory. Existing configuration is backed up before edits. Repeated installation does not duplicate the block. The installer honors the ZDOTDIR visible to its process and refuses unsafe targets.

Settings asks you to select the folder containing your `.zshrc` (your home folder, or your custom `ZDOTDIR`). Choose the same folder for uninstall. This avoids assuming a Finder-launched app inherits shell environment. You can also invoke the bundled installer explicitly from your configured shell:

```zsh
/bin/zsh -f "/Applications/Terminal Helper.app/Contents/Resources/Integration/install.zsh"
```

Use Settings → Uninstall shell integration, then restart open shells. It disables assistance, removes only the owned configuration block and integration, and removes its state. Missing state keeps existing shells inert. After all integrated shells close, you may delete the app and any remaining private support folder. Backups next to your shell configuration remain yours to keep or restore. A partial/edited managed block is rejected; inspect your backup rather than overwriting configuration.

## Limits and performance

Fuzzy correction is limited to one edit, at most 256 sibling entries and 20 candidates, without recursive searching. Native/user-defined zsh completion can still enumerate large directories or run its own logic, so filesystem latency and third-party completions can exceed targets. No hard latency cap is claimed.

The engineering targets are added shell-startup p95 ≤30 ms and first useful suggestion p95 ≤100 ms on a documented fixture. See the actual runner measurements, method, fixture, and remaining checks in [verification](Docs/VERIFICATION.md). Targets are not measurements.

## Build and test remotely

```sh
bash Scripts/build.sh
python3 Tests/Shell/test_pty.py
python3 Tests/Shell/test_install.py
"dist/Terminal Helper.app/Contents/MacOS/TerminalHelper" --self-test
python3 Tests/Performance/measure.py
```

Run on a disposable remote macOS runner with Xcode tools and Python 3. `Scripts/build.sh` compiles both architectures with the macOS 13 deployment target, bundles integration/docs, generates the app icon from native vector drawing, and ad-hoc signs/verifies the app. `VERSION=0.1.0` may be set explicitly. It does not install the app. CI packages a commit-qualified ZIP and SHA-256 checksum, with 14-day artifact retention. Dependencies: system Swift/AppKit, zsh, shell utilities; Python standard library for tests only.

See [architecture](Docs/ARCHITECTURE.md), [manual release checks](Docs/MANUAL-VERIFICATION.md), and the [short roadmap](Docs/ROADMAP.md). Editable vector identity sources live in [Assets](Assets).
