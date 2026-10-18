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
Terminal Helper — unsigned preview distribution limitation

This engineering test artifact is ad-hoc signed, without Developer ID or notarization.
Gatekeeper may refuse to open it. Do not disable Gatekeeper or remove quarantine
as a workaround. A normally trusted download requires a signed, notarized build.

On an approved, normally trusted distribution: drag Terminal Helper.app to
Applications, open it from Applications, and use the terminal-shaped menu-bar
icon. In Settings, install shell integration, open a new terminal, then enable
suggestions. Choose Home folder unless you use a custom ZDOTDIR.

No app installation or execution is performed by this disk image.
HELP
name="Terminal-Helper-${version}-${source_sha:0:12}-universal-test.dmg"
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
printf 'Packaged dist/%s (engineering test build; not notarized)\n' "$name"
