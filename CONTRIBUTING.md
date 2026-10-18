# Contributing

Keep Terminal Helper small: native AppKit, interactive zsh, platform tools, no cloud service or replacement terminal. Read [architecture](Docs/ARCHITECTURE.md), [security](SECURITY.md), and the [manual release checklist](Docs/MANUAL-VERIFICATION.md).

Open a focused pull request explaining the user-visible problem, smallest complete fix and validation. Preserve callers, existing keybindings, shell configuration and privacy. Do not commit build/, dist/, results/, credentials, real history, user datasets or personal configuration.

Use disposable remote macOS runners for this project's source/build work. CI tests actual ZLE through PTYs, repeated installation, case-sensitive paths, native state/controller/worker lifecycle, light/dark Settings renders and the packaged app. A compiler pass alone is insufficient.

For bugs, give the commit/app version, macOS/zsh/terminal versions and a synthetic reproduction. Never paste real command history, secrets, private paths or environment dumps. Report security problems through the private route in SECURITY.md.

No public release, new privileged service, paid dependency, telemetry or architecture expansion is implied by a patch. History suggestions, extra shells and language introspection remain deferred. Contributions are offered under the repository's MIT license.
