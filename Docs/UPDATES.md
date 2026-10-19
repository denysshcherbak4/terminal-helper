# Updates

## Automatic notices in 0.3.1

The current published download is 0.3.1. Version 0.3.1 adds **Check for updates automatically** in Settings, enabled by default; your choice to disable it is preserved.

An automatic check requires **suggestions On** and that checkbox enabled. It can start at normal app launch or when suggestions genuinely change Off→On. It requests the public GitHub release catalog only. No checksum, DMG or app is downloaded until you explicitly choose **Update Now** or invoke the existing manual update action.

With a stable system clock, at most one automatic attempt starts per 24-hour window. The attempt date is recorded when the request starts, so failure or cancellation still uses the window. A backwards clock correction can reset eligibility rather than suppress checks indefinitely. There is no persistent timer/daemon: leaving the app running On overnight does not schedule a midnight or exact daily check. The next eligible launch/enable event is the next opportunity.

The native offer gives three choices:

- **Update Now:** explicitly start the existing verified download/installation flow below.
- **Remind Me Later:** leave the version eligible for the next launch/enable event after the attempt cooldown; no timed reminder is scheduled.
- **Skip This Version:** persist only this exact version's automatic suppression. A later newer published version can still be offered when eligible.

Off cancels pending automatic checking, and late results do not show an offer. Manual Check for Updates, `terminal-helper check` and `terminal-helper update` remain available while Off and ignore the automatic checkbox, cooldown and skipped version. Published numeric release and trust rules below are unchanged.

## One final manual upgrade from 0.2

Automatic installation starts in **0.3.0**. An already-installed 0.2 executable keeps its old behavior: its update command verifies and opens a DMG for manual replacement. Publishing a release cannot change that installed executable.

Download/open the published 0.3 verified DMG, Disable and Quit 0.2, replace the app in Finder, and open 0.3. Update integration if prompted and restart terminal windows. Use `~/Applications/Terminal Helper.app` for installation without administrator rights. After that, 0.3 and later can install subsequent updates in place.

The README links directly to published 0.3. Branches and CI builds do not update installed users.

## Subsequent updates in 0.3 and later

Choose **Check for Updates…** in the menu-bar app/Settings, then choose the offered installation action. Alternatively, after installing integration and opening a new zsh:

```sh
terminal-helper version
terminal-helper check
terminal-helper update
```

`check` only checks. In 0.3+, `update` explicitly requests download and installation of a newer published release. App archives are not downloaded or installed on startup or on a timer. In 0.3.1, the gated automatic check above can request catalog metadata. Explicit commands remain available while suggestions are Off.

The updater verifies the DMG, expected app identity, release version and signature integrity before replacing the installed app. It requests the controller to save Off and quit, swaps the app, refreshes exact owned integration data, and reopens through macOS Launch Services. **Suggestions stay Off. Restart terminal windows, then enable them deliberately.**

It does not edit `.zshrc`, add a new integration block or change settings. Existing integration must match the known installed version; edited or unsafe integration is refused rather than silently overwritten. Existing aliases/functions/commands named `terminal-helper` are preserved; use the app menu in that case. If the app moved, open it and repair integration.

## Supported locations

In-place installation supports exactly `~/Applications/Terminal Helper.app`, or `/Applications/Terminal Helper.app` when your account owns and can write the app and the parent passes safety checks. The home Applications folder is recommended.

There is no `sudo`, administrator prompt or privileged helper. Globally writable parents and other locations are refused. If running from Downloads, a mounted DMG or another folder, quit, move the app in Finder to a supported location, reopen and repair integration before retrying.

## Failure and recovery

Download, checksum, identity, version or signature validation failures leave the old app untouched. Handled installation failures roll back the bundle swap and restore prior owned integration bytes.

A successful installation retains the old app in a private sibling folder:

```text
<Applications folder>/.Terminal-Helper-update-<UUID>/Terminal Helper.app
```

That folder also contains `RECOVERY.txt`. Keep it until the new app works. After quitting the app, open the matching folder in Finder using **Go → Go to Folder** and follow those instructions. App backups are separate from downloaded DMGs and `.zshrc` backups.

The bundle swap is atomic, but app and integration are not one guaranteed transaction across a crash or power loss. An interrupted operation may require manual recovery from the retained backup. On restart, integration mismatch checks prevent claiming stale integration is ready. See [troubleshooting](TROUBLESHOOTING.md).

If macOS blocks reopening, the updater must not bypass it. Users trusting the exact download may need Apple's per-app approval again. Never override malware/damaged-app warnings or managed restrictions, disable Gatekeeper globally or remove quarantine.

## Trust and privacy

In 0.3.1, an eligible launch/enable event can make an automatic metadata-only request while both suggestions and automatic checking are enabled. Manual requests also remain available while Off. There is no persistent daily timer, daemon, account or telemetry. The automatic preference, last attempt date and exact skipped version remain local non-sensitive UserDefaults data. GitHub/CDN sees ordinary network metadata, never terminal contents or local filesystem data.

Metadata is limited to 512 KiB, checksums to 16 KiB and the DMG to 64 MiB. HTTPS origins, exact repository/tag paths, numeric versions, unique asset selection, upload state and sizes are validated. Redirects stay within allowed GitHub HTTPS endpoints; TLS verification is not overridden. Streaming bounds and timeouts apply.

SHA-256 is checked before a downloaded image is used. The staged app's expected bundle identity, release version and signature integrity are also validated before installation. A mismatch fails closed. Both archives and checksums rely on this GitHub repository account and HTTPS; they cannot independently protect against a compromised repository or establish Developer ID trust.

Saved files have mode 600 inside a unique mode-700 folder; existing downloads are not overwritten. Quarantine is preserved through installation and reopening through macOS Launch Services, not stripped to avoid Gatekeeper.

This free ad-hoc-signed beta has no Apple-verified identity or notarization. Managed Macs may refuse it. Offline fixture tests and real URLSession delegate tests do not replace a browser/Finder/native-terminal upgrade on an authorized Mac.
