#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { printf 'ffmpeg is required to encode the demo.\n' >&2; exit 1; }
mkdir -p work/readme-demo docs/assets
swiftc -O scripts/render-demo.swift -o work/readme-demo/render-demo
work/readme-demo/render-demo work/readme-demo/frames docs/assets/clipori-icon.png
ffmpeg -hide_banner -loglevel error -y -framerate 24 -i work/readme-demo/frames/%04d.png \
  -vf 'palettegen=stats_mode=diff' -frames:v 1 work/readme-demo/palette.png
ffmpeg -hide_banner -loglevel error -y -framerate 24 -i work/readme-demo/frames/%04d.png \
  -i work/readme-demo/palette.png -lavfi 'paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle' \
  -loop 0 -gifflags +transdiff docs/assets/clipori-demo.gif
cp work/readme-demo/frames/0080.png docs/assets/clipori-demo-poster.png
printf 'Created docs/assets/clipori-demo.gif and its static poster.\n'
