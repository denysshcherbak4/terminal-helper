#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${VERSION:-0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be numeric major.minor.patch' >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo 'Packaging requires macOS.' >&2; exit 1; }
source_sha="${SOURCE_SHA:-${GITHUB_SHA:-}}"
if [[ -z "$source_sha" ]]; then source_sha="$(git rev-parse HEAD)"; fi
[[ "$source_sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo 'SOURCE_SHA must identify the source commit.' >&2; exit 1; }
app='dist/Terminal Helper.app'
[[ -d "$app" && -f "$app/Contents/MacOS/TerminalHelper" ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
codesign --verify --strict "$app"
mkdir -p build dist
stage="$(mktemp -d build/dmg-stage.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Terminal Helper.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/Installation.txt" <<'HELP'
Terminal Helper — engineering test build

On a trusted, approved distribution, drag Terminal Helper.app to Applications,
then open it and follow Settings: install integration, open a new terminal,
and enable suggestions.

This test artifact is ad-hoc signed, without Developer ID or notarization.
Gatekeeper may refuse to open it. Do not disable Gatekeeper or remove quarantine
as a workaround. A normally trusted download requires a signed, notarized build.

No app installation or execution is performed by this disk image.
HELP
name="Terminal-Helper-${version}-${source_sha:0:12}-universal-test.dmg"
hdiutil create -volname 'Terminal Helper' -srcfolder "$stage" -format UDZO -ov "dist/$name"
hdiutil verify "dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
printf 'Packaged dist/%s (engineering test build; not notarized)\n' "$name"
