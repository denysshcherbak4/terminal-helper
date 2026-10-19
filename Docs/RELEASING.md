# Publish a version

Repository edits do not update installed users. Only published, non-prerelease versions are eligible. Starting in 0.3.1, enabled automatic notices can discover one through a gated metadata check; installation still requires an explicit action. Version **0.3.0** adds in-place installation for subsequent updates; a 0.2 client needs one final manual Finder upgrade.

1. Set the default numeric version in Scripts/build.sh and App/Updates.swift above the currently published **0.3.1**. Never reuse published version assets for different bytes. Keep the current public README download until the new release asset exists.
2. Review the PR and complete ARM/Intel CI: shell/installer/update tests, staged app identity/version/signature validation, supported-path/permission refusal, bundle/integration swap and handled-error rollback, native checks, renders, package verification and measured target misses. For 0.3.1 also verify launch/real-enable eligibility, the 24-hour attempt cooldown (including failure/cancellation and clock rollback), preserved checkbox choice, Off cancellation/late callback suppression, Later/Skip/manual bypass and metadata-only requests. A Terminal.app step can explicitly SKIP.
3. Select one exact-source CI artifact. Both runner packages are universal; never mix archives/checksums from different runs. Verify SHA256SUMS.txt.
4. Prepare a draft Release tagged vX.Y.Z at that exact tested commit, titled Terminal Helper X.Y.Z — community beta. Disclose ad-hoc signing, no Developer ID/notarization and manual-validation limits.
5. Attach Terminal-Helper-X.Y.Z-universal.dmg, its .sha256 file, the app ZIP and SHA256SUMS.txt. The updater needs exactly one matching DMG and one checksum file.
6. Record applicable manual checks. Release notes must disclose default-enabled, On-gated automatic metadata checks, the opt-out checkbox, local preference/date/skipped-version records and the absence of a daily timer or automatic download/install. Public publication requires maintainer approval.
7. After approval, publish with **Set as the latest release**, not GitHub's prerelease flag. The title/body still say community beta. The updater deliberately follows /releases/latest, which excludes prereleases.
8. Verify the public latest-release API and download. Update the README link/version and remove its forthcoming-release wording only after the asset is available.
9. On an authorized Mac, verify the final manual 0.2→0.3 upgrade, opening approval, integration repair and restarted shells. For a subsequent approved newer release, verify explicit automatic installation at ~/Applications, Off-before-quit, retained backup/RECOVERY.txt, integration consistency, Launch Services reopening and manual recovery. Fixtures do not replace this native user flow.

Automatic installation must not elevate or fall back to another destination. It supports exactly ~/Applications/Terminal Helper.app or an eligible user-owned /Applications/Terminal Helper.app. Validation failures leave the old app untouched; handled installation errors roll back. Retain the backup because app and integration are not a guaranteed transaction across a crash or power loss. Quarantine and macOS opening checks remain in effect.

No paid Apple account is required to distribute this ad-hoc beta; it does not gain Developer ID trust or notarization. Explain [Apple's per-app approval](https://support.apple.com/102445); never globally disable Gatekeeper, strip quarantine or override malware/damaged-app warnings. Some users and managed Macs cannot run the beta.

A future identified/notarized path needs securely configured signing material and separate validation. Current CI uses ad-hoc signing and consumes no signing secrets.

## GPLv3 source and notices

The current project is GPL-3.0-only; published versions through v0.3.1 remain
MIT-licensed. Do not replace or relabel their assets. The next public binary
must use a new version number and carry LICENSE and NOTICE in the app's
Contents/Resources/Docs directory.

For every GPL binary release, provide a complete Corresponding Source archive
for the exact build commit next to the binary downloads on the same public
release page, at no extra charge or account requirement. GitHub's generated
source archives are suitable only when they contain every source file and
build/install script needed for that exact artifact. Include any future
submodules, generated source or other required material explicitly when
necessary. Verify the public archive resolves to the tested commit and that
the documented remote macOS build works from it. Identify that source link
and GPL-3.0-only in the release notes. Do not use a different branch tip as
the binary's source. Preserve third-party license notices.

GPL permits commercial redistribution; its source-sharing obligations apply
when conveying covered copies, not merely to private modifications.
