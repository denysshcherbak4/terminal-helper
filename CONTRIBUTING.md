# Contributing

Keep Terminal Helper small: native AppKit, interactive zsh, platform tools, no cloud service or replacement terminal. Read [architecture](Docs/ARCHITECTURE.md), [security](SECURITY.md), and the [manual release checklist](Docs/MANUAL-VERIFICATION.md).

Open a focused pull request explaining the user-visible problem, smallest complete fix and validation. Preserve callers, existing keybindings, shell configuration and privacy. Do not commit build/, dist/, results/, credentials, real history, user datasets or personal configuration.

Use disposable remote macOS runners for this project's source/build work. CI tests actual ZLE through PTYs, repeated installation, case-sensitive paths, native state/controller/worker lifecycle, light/dark Settings renders and the packaged app. A compiler pass alone is insufficient.

## Reproduce verification

Use the [exact remote-runner commands](README.md#verification-and-development). All standalone update fixture programs need `App/State.swift`, `App/Updates.swift` and `App/UpdateInstaller.swift` in the `swiftc` invocation. Build the universal app before running `Tests/UpdateController/main.swift` and pass the built `dist/Terminal Helper.app` path.

Updater fixtures create and remove their bundles/support data in the runner account's **actual home**. Use only a disposable remote macOS runner with no running Terminal Helper instance, no existing `~/Applications/Terminal Helper.app` and no existing `~/Library/Application Support/Terminal Helper`. Tests refuse existing paths; do not delete a real installation to make them run. Personal-Mac installation or testing requires separate authorization.

The automatic policy fixture additionally includes `App/UpdateNotices.swift`; the native `--update-notice-self-test` injects release responses and private preference/state fixtures without network access.

The native `--termination-self-test` and `--update-cancel-self-test` exercise external quit and cancellation of update/integration workers using fixture state. The controller fixture launches an unquarantined CI-built copy, so it does not establish the downloaded-app Gatekeeper or human upgrade flow. Keep explicit SKIP outcomes and failed/cancelled runs separate from verified results.

For bugs, give the commit/app version, macOS/zsh/terminal versions and a synthetic reproduction. Never paste real command history, secrets, private paths or environment dumps. Report security problems through the private route in SECURITY.md.

No public release, new privileged service, paid dependency, telemetry or architecture expansion is implied by a patch. History suggestions, extra shells and language introspection remain deferred. Contributions are offered under the repository's MIT license.
