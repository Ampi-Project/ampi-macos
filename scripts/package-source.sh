#!/bin/bash
set -euo pipefail
# /// Repository root determines source export paths independent of the caller's current directory.
ampi_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ampi_root"
# /// Source tag must be a safe version label; source bytes always come from the checked-out commit.
ampi_tag="${1:?Usage: bash scripts/package-source.sh vVERSION}"
if [[ ! "$ampi_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
    echo "Source tag must look like v0.1.0 or v0.1.0-beta.1." >&2
    exit 2
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Commit or stash source changes before exporting corresponding source." >&2
    exit 1
fi
# /// Exact pinned ZIPFoundation checkout is resolved by the preceding Swift package build.
ampi_dependency="$ampi_root/.build/checkouts/ZIPFoundation"
if [[ "$(git -C "$ampi_dependency" rev-parse HEAD)" != "22787ffb59de99e5dc1fbfe80b19c97a904ad48d" ]]; then
    echo "ZIPFoundation checkout does not match the pinned source revision." >&2
    exit 1
fi
mkdir -p "$ampi_root/dist"
# /// Disposable staging directory holds only exported source; the exit trap removes this generated directory.
ampi_stage="$(mktemp -d "${TMPDIR:-/tmp}/ampi-source.XXXXXX")"
trap 'rm -rf "$ampi_stage"' EXIT
# /// Export folder gives the tarball a single predictable top-level directory.
ampi_folder="Ampi-${ampi_tag}-source"
mkdir -p "$ampi_stage/$ampi_folder/vendor/ZIPFoundation"
git archive HEAD | tar -x -C "$ampi_stage/$ampi_folder"
git -C "$ampi_dependency" archive HEAD | tar -x -C "$ampi_stage/$ampi_folder/vendor/ZIPFoundation"
git rev-parse HEAD > "$ampi_stage/$ampi_folder/SOURCE-COMMIT.txt"
git -C "$ampi_dependency" rev-parse HEAD > "$ampi_stage/$ampi_folder/vendor/ZIPFoundation/SOURCE-COMMIT.txt"
# /// Source asset includes app/build scripts, pinned dependency sources, and licenses without .git or build caches.
ampi_asset="Ampi-${ampi_tag}-source.tar.gz"
# /// macOS filesystem metadata is omitted so AppleDouble sidecars cannot escape the source archive's single root.
COPYFILE_DISABLE=1 tar -czf "$ampi_root/dist/$ampi_asset" -C "$ampi_stage" "$ampi_folder"
cd "$ampi_root/dist"
shasum -a 256 "$ampi_asset" > "$ampi_asset.sha256"
echo "Created $ampi_asset and $ampi_asset.sha256."
