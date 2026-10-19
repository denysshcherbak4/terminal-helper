#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Packaging requires macOS.' >&2; exit 1; }
source_sha="${SOURCE_SHA:-${GITHUB_SHA:-}}"
if [[ -z "$source_sha" ]]; then source_sha="$(git rev-parse HEAD)"; fi
[[ "$source_sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo 'SOURCE_SHA must identify the source commit.' >&2; exit 1; }
app='dist/Terminal Helper.app'
[[ -d "$app" && -f "$app/Contents/MacOS/TerminalHelper" ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Bundle version must be numeric major.minor.patch.' >&2; exit 1; }
[[ -z "${VERSION:-}" || "$VERSION" == "$version" ]] || { echo 'VERSION does not match the built app. Rebuild before packaging.' >&2; exit 1; }
codesign --verify --strict "$app"
mkdir -p build dist
stage="$(mktemp -d build/dmg-stage.XXXXXX)"
mount="$(mktemp -d build/dmg-mount.XXXXXX)"
mounted=0
cleanup() {
    if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount" -quiet || true; fi
    rm -rf "$stage"
    rmdir "$mount" 2>/dev/null || true
}
trap cleanup EXIT
ditto "$app" "$stage/Terminal Helper.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/README.txt" <<'HELP'
Terminal Helper — free beta for macOS 13+ (Apple silicon and Intel)

This beta is ad-hoc signed. It has no Developer ID signature or Apple
notarization. Download only from the project's published GitHub release and
verify its checksum before trusting it.

1. Drag Terminal Helper.app to Applications inside your home folder (~/Applications)
   for updates without an administrator password, then open it from there.
   /Applications also works if your account owns the app and can write there.
2. If you trust this unmodified download and macOS reports an unidentified
   developer or that Apple cannot check the app, after trying to open it use
   System Settings > Privacy & Security > Open Anyway, then confirm Open.
   This is Apple's per-app exception; do not disable Gatekeeper globally or
   remove quarantine. Do not override a damaged-app or malware warning.
   Apple's instructions: https://support.apple.com/102445
3. Use the terminal-shaped menu-bar icon. In Settings, install shell integration,
   open a new terminal window, and enable suggestions. Choose Home folder unless
   you configured a custom ZDOTDIR.

Updating 0.2: one final manual replacement is needed to acquire the new updater.
From 0.3 onward use terminal-helper update or Check for Updates / Install Update.
Requested installation verifies the download, replaces the app and owned integration,
keeps a recovery copy, and reopens through macOS security checks. Restart terminal
windows and enable suggestions afterward. No background polling or sudo is used.

From 0.3.1, enabled automatic checks request release metadata on app launch or
when suggestions are enabled, at most once per 24 hours. Suggestions must be On.
No recurring timer is installed. Settings can disable automatic checks. Notices
offer Update Now, Remind Me Later or Skip This Version; downloads/installations
still require your action. Manual checks work while Off and ignore skipped versions.

This disk image does not install or execute anything automatically.
HELP
name="Terminal-Helper-${version}-universal.dmg"
hdiutil create -volname 'Terminal Helper' -srcfolder "$stage" -format UDZO -ov "dist/$name"
hdiutil verify "dist/$name"
hdiutil attach "dist/$name" -readonly -nobrowse -mountpoint "$mount" -quiet
mounted=1
[[ -f "$mount/Terminal Helper.app/Contents/MacOS/TerminalHelper" ]] || { echo 'DMG is missing the app.' >&2; exit 1; }
[[ -L "$mount/Applications" && "$(readlink "$mount/Applications")" == /Applications ]] || { echo 'DMG Applications link is invalid.' >&2; exit 1; }
xcrun lipo "$mount/Terminal Helper.app/Contents/MacOS/TerminalHelper" -verify_arch arm64 x86_64
codesign --verify --strict "$mount/Terminal Helper.app"
hdiutil detach "$mount" -quiet
mounted=0
(
    cd dist
    shasum -a 256 "$name" > "$name.sha256"
    files=(./*.zip ./*.dmg)
    for file in "${files[@]}"; do
        [[ ! -f "$file" ]] || shasum -a 256 "$file"
    done > SHA256SUMS.txt
)
rm -f dist/SHA256SUMS
printf 'Packaged dist/%s (free ad-hoc beta; not notarized)\n' "$name"
