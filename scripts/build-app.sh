#!/bin/bash
set -euo pipefail
# /// Repository root resolved from the script location, independent of the caller's directory.
ampi_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ampi_root"
# /// Swift build mode requested by the caller, defaulting to debug.
configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 2
fi
swift build --configuration "$configuration"
# /// SwiftPM output directory containing the executable and processed resource bundles.
ampi_bin="$(swift build --configuration "$configuration" --show-bin-path)"
# /// Destination of the locally packaged macOS application bundle.
ampi_app="$ampi_root/dist/Ampi.app"
mkdir -p "$ampi_app/Contents/MacOS" "$ampi_app/Contents/Resources"
cp "$ampi_bin/Ampi" "$ampi_app/Contents/MacOS/Ampi"
# /// Each generated SwiftPM resource bundle copied alongside the application executable.
for bundle in "$ampi_bin"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    ditto "$bundle" "$ampi_app/Contents/Resources/$(basename "$bundle")"
done
cp LICENSE "$ampi_app/Contents/Resources/LICENSE"
# /// Dependency notices accompany the statically linked ZIP parser in local app bundles.
ditto licenses "$ampi_app/Contents/Resources/licenses"
cat > "$ampi_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ampi</string>
<key>CFBundleIdentifier</key><string>org.ampi-project.macos</string>
<key>CFBundleName</key><string>Ampi</string>
<key>CFBundleDisplayName</key><string>Ampi</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Ampi contributors. GPL-3.0-only.</string>
</dict></plist>
PLIST
codesign --force --sign - "$ampi_app"
echo "Built $ampi_app (local ad-hoc signature; not a notarized release)."
