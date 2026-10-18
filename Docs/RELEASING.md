# Publish a version

Repository edits do not update installed users. They explicitly check the latest published, non-prerelease version.

1. Change the default numeric X.Y.Z in Scripts/build.sh and the README download/version links. Never reuse a published version for different bytes.
2. Review the PR and complete ARM/Intel CI: shell/installer/update tests, native checks, renders, package verification and measured target misses. A Terminal.app step can explicitly SKIP.
3. Select one exact-source CI artifact. Both runner packages are universal; never mix archives/checksums from different runs. Verify SHA256SUMS.txt.
4. Prepare a draft Release tagged vX.Y.Z at that exact tested commit, titled Terminal Helper X.Y.Z — community beta. Disclose ad-hoc signing, no Developer ID/notarization and manual-validation limits.
5. Attach Terminal-Helper-X.Y.Z-universal.dmg, its .sha256 file, the app ZIP and SHA256SUMS.txt. The updater needs exactly one matching DMG and one checksum file.
6. Record applicable manual checks. Public publication requires maintainer approval.
7. After approval, publish with **Set as the latest release**, not GitHub's prerelease flag. The title/body still say community beta. The updater deliberately follows /releases/latest, which excludes prereleases.
8. Verify the README download and public latest-release API. On an authorized Mac, test updating from the prior version, quarantine, deliberate Finder replacement, integration update and restarted shells.

No paid Apple account is required to distribute this ad-hoc beta; it does not gain Developer ID trust or notarization. Explain [Apple's per-app approval](https://support.apple.com/102445); never globally disable Gatekeeper, strip quarantine or override malware/damaged-app warnings. Some users and managed Macs cannot run the beta.

A future identified/notarized path needs securely configured signing material and separate validation. Current CI uses ad-hoc signing and consumes no signing secrets.
