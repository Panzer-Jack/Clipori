#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
architecture="${CLIPORI_ARCH:-$(uname -m)}"
case "$configuration" in debug|release) ;; *) printf 'Invalid configuration: %s\n' "$configuration" >&2; exit 1 ;; esac
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac

version="${CLIPORI_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
source scripts/release-metadata.sh "app-v$version"
build_number="${CLIPORI_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)}"
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Build number must be a positive integer.\n' >&2
  exit 1
fi

swift_args=(-c "$configuration" --arch "$architecture")
swift build "${swift_args[@]}"
binary_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
output_dir="${CLIPORI_BUILD_DIR:-build}"
bundle="$output_dir/Clipori.app"
staging="$(mktemp -d "${TMPDIR:-/tmp}/clipori-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
staged_bundle="$staging/Clipori.app"
mkdir -p "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp "$binary_dir/Clipori" "$staged_bundle/Contents/MacOS/Clipori"
cp Resources/Info.plist "$staged_bundle/Contents/Info.plist"
cp LICENSE "$staged_bundle/Contents/Resources/LICENSE"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $app_version" "$staged_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$staged_bundle/Contents/Info.plist"
# Use the same checked-in artwork as the Xcode target and documentation.
cp Resources/AppIcon.icns "$staged_bundle/Contents/Resources/AppIcon.icns"
test -s "$staged_bundle/Contents/Resources/AppIcon.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$staged_bundle/Contents/Info.plist")" = AppIcon.icns
codesign --force --sign - "$staged_bundle"
codesign --verify --deep --strict "$staged_bundle"
if [[ "$(lipo -archs "$staged_bundle/Contents/MacOS/Clipori")" != "$architecture" ]]; then
  printf 'Built executable does not match the requested architecture.\n' >&2
  exit 1
fi
mkdir -p "$output_dir"
rm -rf "$bundle"
ditto "$staged_bundle" "$bundle"
printf 'Built %s (%s, version %s, build %s)\n' "$bundle" "$architecture" "$app_version" "$build_number"
