#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Export only the public landing page and its media; planning and source files stay out.
output="build/site"
mkdir -p "$output/assets"
cp docs/index.html docs/site.css docs/site.js docs/motion.css docs/motion.js docs/.nojekyll "$output/"
for asset in clipori-icon.png clipori-demo-en.mp4 clipori-demo-zh.mp4 \
  clipori-demo-poster-en.jpg clipori-demo-poster-zh.jpg clipori-demo.gif clipori-demo-zh.gif; do
  test -s "docs/assets/$asset"
  cp "docs/assets/$asset" "$output/assets/"
done
printf 'Website exported to %s\n' "$output"
