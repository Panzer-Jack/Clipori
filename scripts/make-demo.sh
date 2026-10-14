#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { printf 'ffmpeg is required to encode the demo.\n' >&2; exit 1; }
mkdir -p work/readme-demo docs/assets
swiftc -O scripts/render-demo.swift -o work/readme-demo/render-demo
swiftc -O scripts/render-daily-demo.swift -o work/readme-demo/render-daily-demo
# A shorter timeline must not include stale frames from the previous render.
rm -f work/readme-demo/frames/*.png work/readme-demo/daily/*.png
work/readme-demo/render-demo work/readme-demo/frames docs/assets/clipori-icon.png
work/readme-demo/render-daily-demo work/readme-demo/daily en
# One walkthrough: the original shelf sequence, followed by daily notes.
# Keep the shelf animation at 50 fps; hold each daily-notes frame for five ticks.
sequence='[0:v]pad=1200:800:0:40:color=0x16131D,setsar=1[shelf];[1:v]fps=50,setsar=1[daily];[shelf][daily]concat=n=2:v=1:a=0'
ffmpeg -hide_banner -loglevel error -y \
  -framerate 50 -i work/readme-demo/frames/%04d.png -framerate 10 -i work/readme-demo/daily/%04d.png \
  -filter_complex "$sequence,palettegen=stats_mode=diff" -frames:v 1 work/readme-demo/palette.png
ffmpeg -hide_banner -loglevel error -y \
  -framerate 50 -i work/readme-demo/frames/%04d.png -framerate 10 -i work/readme-demo/daily/%04d.png \
  -i work/readme-demo/palette.png \
  -filter_complex "$sequence[walkthrough];[walkthrough][2:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 -gifflags +transdiff docs/assets/clipori-demo.gif
ffmpeg -hide_banner -loglevel error -y -i work/readme-demo/frames/0340.png \
  -vf 'pad=1200:800:0:40:color=0x16131D' -frames:v 1 docs/assets/clipori-demo-poster.png
printf 'Created the combined docs/assets/clipori-demo.gif and its static poster.\n'
