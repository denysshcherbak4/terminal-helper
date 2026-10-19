#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${VERSION:-0.3.1}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be numeric major.minor.patch' >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo 'Build requires macOS with Xcode command-line tools.' >&2; exit 1; }
mkdir -p build dist
app='dist/Terminal Helper.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Integration" "$app/Contents/Resources/Docs"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
    xcrun swiftc -O -sdk "$sdk" -target "$arch-apple-macosx13.0" App/State.swift App/Icon.swift App/IntegrationWorker.swift App/Updates.swift App/UpdateInstaller.swift App/UpdateNotices.swift App/main.swift -o "build/TerminalHelper-$arch" -framework AppKit
done
xcrun lipo -create build/TerminalHelper-arm64 build/TerminalHelper-x86_64 -output "$app/Contents/MacOS/TerminalHelper"
xcrun swiftc -O App/Icon.swift Scripts/GenerateIcon.swift -o build/generate-icon -framework AppKit
build/generate-icon build/AppIcon.iconset
xcrun iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp Integration/terminal-helper.zsh Integration/install.zsh Integration/uninstall.zsh "$app/Contents/Resources/Integration/"
cp README.md LICENSE PRIVACY.md App/Help.txt "$app/Contents/Resources/Docs/"
if [[ -d Docs ]]; then cp -R Docs/. "$app/Contents/Resources/Docs/"; fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.denysshcherbak4.terminal-helper</string>
<key>CFBundleName</key><string>Terminal Helper</string>
<key>CFBundleDisplayName</key><string>Terminal Helper</string>
<key>CFBundleExecutable</key><string>TerminalHelper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Free beta builds use ad-hoc integrity signing; this is not Developer ID or notarization.
codesign --force --sign - "$app"
codesign --verify --strict "$app"
"$app/Contents/MacOS/TerminalHelper" --self-test
printf 'Built %s (macOS 13+, universal arm64/x86_64, ad-hoc signed)\n' "$app"
