#!/bin/bash
set -euo pipefail
# /// Repository containing the independently buildable macOS package and distribution directory.
ampi_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ampi_root"
# /// Validated release tag is passed through the environment to bundle metadata, never interpolated as shell code.
ampi_tag="${1:?Usage: bash scripts/package-release.sh vVERSION [arm64|x86_64]}"
# /// Requested asset architecture defaults to the native machine; this script does not cross-compile.
ampi_arch="${2:-$(uname -m)}"
if [[ "$ampi_arch" != "arm64" && "$ampi_arch" != "x86_64" ]]; then
    echo "Architecture must be arm64 or x86_64." >&2
    exit 2
fi
AMPI_RELEASE_TAG="$ampi_tag" bash scripts/build-app.sh release
# /// Optimized bundle is checked before creating an asset; an incorrectly labelled binary is never uploaded.
ampi_app="$ampi_root/dist/Ampi.app"
if [[ "$(lipo -archs "$ampi_app/Contents/MacOS/Ampi")" != "$ampi_arch" ]]; then
    echo "The app's actual architecture does not match $ampi_arch." >&2
    exit 1
fi
plutil -lint "$ampi_app/Contents/Info.plist"
codesign --verify --deep --strict "$ampi_app"
test -f "$ampi_app/Contents/Resources/LICENSE"
test -f "$ampi_app/Contents/Resources/licenses/ZIPFoundation.txt"
# /// Version and architecture distinguish downloadable ZIPs without needing a universal-binary build.
ampi_asset="Ampi-${ampi_tag}-macos-${ampi_arch}.zip"
cd "$ampi_root/dist"
ditto -c -k --sequesterRsrc --keepParent "$ampi_app" "$ampi_asset"
unzip -tq "$ampi_asset"
shasum -a 256 "$ampi_asset" > "$ampi_asset.sha256"
echo "Created $ampi_asset and $ampi_asset.sha256 (ad-hoc signed, not notarized)."
