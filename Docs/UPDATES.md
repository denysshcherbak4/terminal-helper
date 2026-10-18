# Updates

Choose Check for Updates… in the menu-bar app/Settings, or run:

```sh
terminal-helper version
terminal-helper check
terminal-helper update
```

Install/update integration and open a new zsh first. An existing command, alias or function named terminal-helper is preserved; use the app menu in that case. If the app moved, open it and repair integration.

Checks compare the local numeric app version with the latest **published, non-prerelease** vX.Y.Z release. Drafts, prereleases, branches and commits are not offered. No published release is explained explicitly; offline/rate-limit failures are not reported as “up to date.”

Downloading fetches the checksum and matching universal DMG, verifies bytes, saves privately under Downloads, retains quarantine, and opens the disk image. Then:

1. Disable and Quit the old app.
2. Replace it in the same Applications folder using Finder.
3. Open it. Users trusting the exact source may need Apple's per-app Privacy & Security → Open Anyway approval again. Never override malware/damaged-app warnings or managed restrictions.
4. Choose Update shell integration if prompted.
5. Restart terminal windows and enable suggestions.

The updater never executes a downloaded app/script, self-replaces an app or asks for elevation.

## Trust and privacy

Requests occur only after an explicit action, including while suggestions are Off. There is no background checker, startup request, account or telemetry. GitHub/CDN sees ordinary network metadata, never terminal contents or local filesystem data.

Metadata is limited to 512 KiB, checksums to 16 KiB and the DMG to 64 MiB. HTTPS origins, exact repository/tag paths, numeric versions, unique asset selection, upload state and sizes are validated. Redirects stay within allowed GitHub HTTPS endpoints; TLS verification is not overridden. Streaming bounds and timeouts apply.

SHA-256 is checked before saving/opening. A mismatch fails closed. Both archives and checksums rely on this GitHub repository account and HTTPS; they cannot independently protect against a compromised repository or establish Developer ID trust.

Saved files have mode 600 inside a unique mode-700 folder; existing downloads are not overwritten. Quarantine is applied before success, not stripped to avoid Gatekeeper.

This free ad-hoc-signed beta has no Apple-verified identity or notarization. Managed Macs may refuse it. Offline fixture tests and real URLSession delegate tests do not replace a browser/Finder/native-terminal upgrade on an authorized Mac.
