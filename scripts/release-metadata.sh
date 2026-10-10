#!/bin/bash
# Can also be sourced by the packaging scripts to share version validation.
set -euo pipefail

release_tag="${1:-}"
tag_pattern='^app-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$release_tag" =~ $tag_pattern ]]; then
  printf 'Expected app-vX.Y.Z or app-vX.Y.Z-beta.1, got: %s\n' "$release_tag" >&2
  exit 1
fi

release_version="${release_tag#app-v}"
app_version="${release_version%%-*}"
is_prerelease=false
if [[ "$release_version" == *-* ]]; then
  is_prerelease=true
  IFS='.' read -r -a identifiers <<< "${release_version#*-}"
  for identifier in "${identifiers[@]}"; do
    if [[ "$identifier" =~ ^0[0-9]+$ ]]; then
      printf 'Numeric prerelease identifiers cannot have leading zeros.\n' >&2
      exit 1
    fi
  done
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'tag=%s\nversion=%s\napp_version=%s\nprerelease=%s\n' \
    "$release_tag" "$release_version" "$app_version" "$is_prerelease"
fi
