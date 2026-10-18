# Security policy

## Report privately

Use [Report a vulnerability](https://github.com/denysshcherbak4/terminal-helper/security/advisories/new). GitHub private vulnerability reporting is enabled. Do not put exploit details, credentials, real command history, private filenames or personal data in public issues.

Include the exact app/commit version, macOS/zsh versions, expected behavior, a minimal synthetic reproduction, and impact. Redact personal paths and use disposable fixture files. No response-time or remediation SLA is promised; this preview is maintained on a best-effort basis.

## Supported scope

The current published community beta and main branch are the reviewed scope. A passing CI build is not a claim of public-release readiness or complete security.

Security properties:
- Completion must not evaluate or execute typed input. Accepting a suggestion edits text only; execution is a separate action.
- Off gates generation and acceptance in already-open integrated shells. Missing, malformed, unsafe or unreadable state fails closed.
- Private state and app-path metadata are non-executable data, updated atomically. No polling or daemon. Suggestions have no network dependency; explicit update actions contact GitHub.
- Install/uninstall must preserve unrelated shell configuration, use backups and atomic replacement, reject unsafe targets, serialize install/uninstall and refuse detected configuration changes, and remove only owned content.
- Bundled installer processes run without elevated privileges in an owned process group. Quit disables assistance before terminating that group.
- Filenames and descriptions are untrusted. User-configured completion definitions themselves are executable code within the existing zsh trust boundary.

## Distribution

Current preview builds have ad-hoc integrity signatures, no Developer ID identity and no notarization. SHA-256 detects mismatched bytes; it does not replace a trusted signing identity. Do not disable Gatekeeper globally or remove quarantine protection to make installation work.

The free ad-hoc community beta can be distributed without Apple Developer membership, but does not provide Apple publisher verification or notarization. Users trusting the exact source may follow [Apple’s per-app opening approval](https://support.apple.com/102445); never override malware/damaged-app warnings or organization restrictions. An identified/notarized build is a separate future distribution path. See [Apple's distribution guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

CI runs unprivileged project code only on disposable GitHub-hosted macOS runners with contents-read permission and pinned Actions. PR jobs receive no signing secrets. Signing credentials must be configured through GitHub encrypted secrets/environment protection, never in issues, logs, source or chat. A public release requires separate maintainer approval.

## Update trust boundary

Only explicit menu/terminal update actions contact GitHub, including while suggestions are Off. There are no timers/startup requests. Version, origin, redirect, size and checksum validation is bounded; downloaded DMGs retain quarantine. From 0.3, explicit installation revalidates published checksums, mounts a private snapshot read-only, verifies bundle identity/version/signature without executing downloaded code, and atomically exchanges only the supported writable app path. Existing owned integration data is upgraded without sourcing it or editing shell configuration; handled failures roll back, and a recovery copy is retained. Reopening goes through Launch Services and may require macOS approval. No elevation or quarantine removal is performed. Both checksums and assets trust this repository account and HTTPS, not an independent publisher identity. See [updates](Docs/UPDATES.md).

## Review limits

The independent review reads source through GitHub APIs. The formal Codex Security orchestrator requires a local Git checkout, which conflicts with this project's remote-only development boundary; it has not been run. Do not describe the manual source review as a formal scanner result or a security guarantee. Actual Terminal.app/iTerm2, VoiceOver, oldest-macOS and slow-filesystem checks remain explicit release gates.
