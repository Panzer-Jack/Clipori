#!/bin/bash
# Called only by the release job, after both architecture builds succeed.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release-metadata.sh "${1:-}"
release_dir="${2:-build/release}"
release_dir="$(cd "$release_dir" && pwd)"
: "${GH_REPO:?Set GH_REPO to the target owner/repository}"

assets=()
for architecture in arm64 x86_64; do
  for extension in dmg zip; do
    asset="$release_dir/Clipori-$release_version-macOS-$architecture.$extension"
    if [[ ! -s "$asset" ]]; then
      printf 'Missing release asset: %s\n' "$asset" >&2
      exit 1
    fi
    assets+=("$asset")
  done
  (
    cd "$release_dir"
    # Require both exact filenames and their digests, not a partial manifest.
    diff "SHA256SUMS-$architecture.txt" <(shasum -a 256 \
      "Clipori-$release_version-macOS-$architecture.dmg" \
      "Clipori-$release_version-macOS-$architecture.zip")
  )
done
cat "$release_dir/SHA256SUMS-arm64.txt" "$release_dir/SHA256SUMS-x86_64.txt" > "$release_dir/SHA256SUMS.txt"
assets+=("$release_dir/SHA256SUMS.txt")

# A published release is never overwritten, including on a workflow rerun.
if draft_state="$(gh release view "$release_tag" --repo "$GH_REPO" --json isDraft --jq .isDraft)"; then
  if [[ "$draft_state" == false ]]; then
    printf 'Release %s is already published; leaving it unchanged.\n' "$release_tag"
    exit 0
  fi
  if [[ "$draft_state" != true ]]; then
    printf 'Unexpected release state; refusing to modify it.\n' >&2
    exit 1
  fi
else
  # --verify-tag prevents GitHub from inventing a tag at the default branch.
  # Network/auth errors also fail here; they cannot overwrite another release.
  gh release create "$release_tag" --repo "$GH_REPO" --verify-tag --draft \
    --title "Clipori $release_version" --prerelease="$is_prerelease" \
    --generate-notes --notes-file .github/RELEASE_NOTES.md
fi

# Failed uploads leave a draft that a later run can resume.
gh release upload "$release_tag" "${assets[@]}" --repo "$GH_REPO" --clobber
publish_args=(--draft=false --prerelease="$is_prerelease" --verify-tag)
if [[ "$is_prerelease" == true ]]; then publish_args+=(--latest=false); fi
gh release edit "$release_tag" --repo "$GH_REPO" "${publish_args[@]}"
gh release view "$release_tag" --repo "$GH_REPO" --json url --jq .url
