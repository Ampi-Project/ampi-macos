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
# /// Optional release tag accepts vMAJOR.MINOR.PATCH with a simple prerelease suffix; XML/shell metacharacters are rejected.
ampi_release_tag="${AMPI_RELEASE_TAG:-}"
# /// Numeric marketing version defaults locally; tagged releases derive it from the validated tag.
ampi_version="${AMPI_VERSION:-0.1.0}"
if [[ -n "$ampi_release_tag" ]]; then
    if [[ ! "$ampi_release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
        echo "Release tag must look like v0.1.0 or v0.1.0-beta.1." >&2
        exit 2
    fi
    ampi_version="${ampi_release_tag#v}"
    ampi_version="${ampi_version%%-*}"
fi
# /// Positive bundle build number is independent of the release's marketing version.
ampi_build_number="${AMPI_BUILD_NUMBER:-1}"
if [[ ! "$ampi_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$ampi_build_number" =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo "AMPI_VERSION must have three numeric components; AMPI_BUILD_NUMBER must be 1–9999." >&2
    exit 2
fi
swift build --force-resolved-versions --configuration "$configuration"
# /// SwiftPM output directory containing the executable and processed resource bundles.
ampi_bin="$(swift build --configuration "$configuration" --show-bin-path)"
# /// Destination of the locally packaged macOS application bundle.
ampi_app="$ampi_root/dist/Ampi.app"
# /// Only this generated app bundle is replaced, preventing stale resources/signatures from an earlier local build.
rm -rf "$ampi_app"
mkdir -p "$ampi_app/Contents/MacOS" "$ampi_app/Contents/Resources"
cp "$ampi_bin/Ampi" "$ampi_app/Contents/MacOS/Ampi"
# /// Production/dependency resource bundles are copied; unit-test fixture bundles stay in the build directory.
for bundle in "$ampi_bin"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    [[ "$bundle" == *Tests.bundle ]] && continue
    ditto "$bundle" "$ampi_app/Contents/Resources/$(basename "$bundle")"
done
cp LICENSE "$ampi_app/Contents/Resources/LICENSE"
# /// Dependency notices accompany the statically linked ZIP parser in local app bundles.
ditto licenses "$ampi_app/Contents/Resources/licenses"
cat > "$ampi_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ampi</string>
<key>CFBundleIdentifier</key><string>org.ampi-project.macos</string>
<key>CFBundleName</key><string>Ampi</string>
<key>CFBundleDisplayName</key><string>Ampi</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$ampi_version</string>
<key>CFBundleVersion</key><string>$ampi_build_number</string>
<key>AmpiReleaseTag</key><string>${ampi_release_tag:-local}</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Ampi contributors. GPL-3.0-only.</string>
</dict></plist>
PLIST
codesign --force --sign - "$ampi_app"
echo "Built $ampi_app (local ad-hoc signature; not a notarized release)."
