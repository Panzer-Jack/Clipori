#!/bin/bash
# Exercises release failures and retries without contacting GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipori-release-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
for tag in app-v0.1.0 app-v12.3.4 app-v0.2.0-beta.1 app-v1.0.0-rc.0; do
  ./scripts/release-metadata.sh "$tag" > "$test_dir/metadata" || fail "valid tag $tag"
done
./scripts/release-metadata.sh app-v0.2.0-beta.1 > "$test_dir/metadata"
grep -qx 'version=0.2.0-beta.1' "$test_dir/metadata"
grep -qx 'app_version=0.2.0' "$test_dir/metadata"
grep -qx 'prerelease=true' "$test_dir/metadata"
for tag in '' main v1.2.3 app-v1.2 app-v01.2.3 app-v1.2.3-beta.01 app-v1.2.3- 'app-v1.2.3;echo bad'; do
  if ./scripts/release-metadata.sh "$tag" > /dev/null 2>&1; then fail "invalid tag accepted: $tag"; fi
done

mkdir -p "$test_dir/bin" "$test_dir/state" "$test_dir/assets"
cat > "$test_dir/bin/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_STATE_DIR/calls"
case "$1 $2" in
  'release view')
    if [[ "$*" == *'--json url'* ]]; then
      printf 'https://example.invalid/release\n'
    elif [[ -f "$MOCK_STATE_DIR/draft" ]]; then
      cat "$MOCK_STATE_DIR/draft"
    else
      exit 1
    fi
    ;;
  'release create')
    if [[ "$MOCK_SCENARIO" == create_failure ]]; then exit 1; fi
    [[ "$*" == *'--draft'* && "$*" == *'--verify-tag'* ]]
    printf 'true\n' > "$MOCK_STATE_DIR/draft"
    ;;
  'release upload')
    [[ "$(cat "$MOCK_STATE_DIR/draft")" == true ]]
    if [[ "$MOCK_SCENARIO" == upload_failure ]]; then exit 1; fi
    ;;
  'release edit')
    [[ "$*" == *'--draft=false'* ]]
    printf 'false\n' > "$MOCK_STATE_DIR/draft"
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$test_dir/bin/gh"

make_assets() {
  for architecture in arm64 x86_64; do
    for extension in dmg zip; do
      printf 'Fixture %s %s\n' "$architecture" "$extension" > "$test_dir/assets/Clipori-$1-macOS-$architecture.$extension"
    done
    (cd "$test_dir/assets" && shasum -a 256 "Clipori-$1-macOS-$architecture.dmg" "Clipori-$1-macOS-$architecture.zip" > "SHA256SUMS-$architecture.txt")
  done
}
run_publish() {
  PATH="$test_dir/bin:$PATH" MOCK_STATE_DIR="$test_dir/state" MOCK_SCENARIO="$1" \
    GH_REPO=example/Clipori GH_TOKEN=unused \
    ./scripts/publish-release.sh "${2:-app-v0.1.0}" "$test_dir/assets" > "$test_dir/result" 2>&1
}
reset_state() { rm -f "$test_dir/state/draft" "$test_dir/state/calls"; }

make_assets 0.1.0
run_publish success || fail 'initial release'
[[ "$(cat "$test_dir/state/draft")" == false ]] || fail 'release was not published'
[[ "$(wc -l < "$test_dir/assets/SHA256SUMS.txt" | tr -d ' ')" == 4 ]] || fail 'checksum count'
rm "$test_dir/state/calls"
run_publish success || fail 'published release rerun'
if grep -Eq 'release (create|upload|edit)' "$test_dir/state/calls"; then fail 'published release was modified'; fi

reset_state
if run_publish upload_failure; then fail 'failed upload reported success'; fi
[[ "$(cat "$test_dir/state/draft")" == true ]] || fail 'failed upload must leave a draft'
if grep -q 'release edit' "$test_dir/state/calls"; then fail 'published after a failed upload'; fi
rm "$test_dir/state/calls"
run_publish success || fail 'draft retry'
if grep -q 'release create' "$test_dir/state/calls"; then fail 'retry recreated the draft'; fi

reset_state
if run_publish create_failure; then fail 'failed creation reported success'; fi
if grep -Eq 'release (upload|edit)' "$test_dir/state/calls"; then fail 'continued after creation failure'; fi

reset_state
printf 'corrupted\n' >> "$test_dir/assets/Clipori-0.1.0-macOS-arm64.zip"
if run_publish success; then fail 'corrupt asset was accepted'; fi
[[ ! -e "$test_dir/state/calls" ]] || fail 'GitHub contacted before checksum verification'
make_assets 0.1.0
sed -n '1p' "$test_dir/assets/SHA256SUMS-arm64.txt" > "$test_dir/partial-checksums"
cp "$test_dir/partial-checksums" "$test_dir/assets/SHA256SUMS-arm64.txt"
if run_publish success; then fail 'incomplete checksum manifest accepted'; fi
[[ ! -e "$test_dir/state/calls" ]] || fail 'GitHub contacted with incomplete checksums'
make_assets 0.1.0
rm "$test_dir/assets/Clipori-0.1.0-macOS-x86_64.dmg"
if run_publish success; then fail 'incomplete architecture set accepted'; fi
[[ ! -e "$test_dir/state/calls" ]] || fail 'GitHub contacted with missing assets'

make_assets 0.2.0-beta.1
run_publish success app-v0.2.0-beta.1 || fail 'prerelease'
grep -q 'release edit .*--prerelease=true.*--latest=false' "$test_dir/state/calls" || fail 'prerelease could replace latest'
printf 'Release checks passed: tag validation, complete assets, checksums, publishing, retries, failures, and prereleases.\n'
