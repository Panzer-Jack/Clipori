#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release-metadata.sh "${1:-}"
architecture="${2:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac

release_dir="${CLIPORI_RELEASE_DIR:-build/release}"
mkdir -p "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
CLIPORI_ARCH="$architecture" CLIPORI_VERSION="$release_version" \
  CLIPORI_BUILD_DIR="$release_dir/app-$architecture" ./scripts/build-app.sh release
bundle="$release_dir/app-$architecture/Clipori.app"
asset_name="Clipori-$release_version-macOS-$architecture"

staging="$(mktemp -d "${TMPDIR:-/tmp}/clipori-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$bundle" "$staging/Clipori.app"
ln -s /Applications "$staging/Applications"

ditto -c -k --sequesterRsrc --keepParent "$bundle" "$release_dir/$asset_name.zip"
hdiutil create -volname Clipori -srcfolder "$staging" -ov -format UDZO "$release_dir/$asset_name.dmg"
hdiutil verify "$release_dir/$asset_name.dmg"
(
  cd "$release_dir"
  shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > "SHA256SUMS-$architecture.txt"
)
printf 'Packaged %s in %s\n' "$asset_name" "$release_dir"
