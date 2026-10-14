#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { printf 'ffmpeg is required to encode the demo.\n' >&2; exit 1; }
mkdir -p work/readme-demo/assets docs/assets
swiftc -O scripts/render-demo.swift -o work/readme-demo/render-demo
swiftc -O scripts/render-daily-demo.swift -o work/readme-demo/render-daily-demo
# Keep the shelf's 50 fps motion and hold each daily-note frame for five ticks.
sequence='[0:v]pad=1200:800:0:40:color=0x16131D,setsar=1[shelf];[1:v]fps=50,setsar=1[daily];[shelf][daily]concat=n=2:v=1:a=0'
for language in en zh; do
  frames="work/readme-demo/$language"
  mkdir -p "$frames/shelf" "$frames/daily"
  rm -f "$frames/shelf"/*.png "$frames/daily"/*.png
  work/readme-demo/render-demo "$frames/shelf" docs/assets/clipori-icon.png "$language"
  work/readme-demo/render-daily-demo "$frames/daily" "$language"
  gif="clipori-demo.gif"
  if [ "$language" = zh ]; then gif="clipori-demo-zh.gif"; fi
  inputs=(-framerate 50 -i "$frames/shelf/%04d.png" -framerate 10 -i "$frames/daily/%04d.png")
  ffmpeg -hide_banner -loglevel error -y "${inputs[@]}" \
    -filter_complex "$sequence,palettegen=stats_mode=diff" -frames:v 1 "$frames/palette.png"
  ffmpeg -hide_banner -loglevel error -y "${inputs[@]}" -i "$frames/palette.png" \
    -filter_complex "$sequence[walkthrough];[walkthrough][2:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
    -loop 0 -gifflags +transdiff "work/readme-demo/assets/$gif"
  # Encode video from the same source frames, avoiding GIF palette artifacts.
  ffmpeg -hide_banner -loglevel error -y "${inputs[@]}" -filter_complex "$sequence" \
    -an -c:v libx264 -crf 23 -preset slow -pix_fmt yuv420p -movflags +faststart \
    "work/readme-demo/assets/clipori-demo-$language.mp4"
  # The pinned daily note is visible before playback, including reduced-motion mode.
  ffmpeg -hide_banner -loglevel error -y -i "$frames/daily/0140.png" -frames:v 1 -q:v 2 \
    "work/readme-demo/assets/clipori-demo-poster-$language.jpg"
  bytes=$(wc -c < "work/readme-demo/assets/$gif")
  if [ "$bytes" -ge 26214400 ]; then
    printf '%s exceeds the website 25 MiB asset limit.\n' "$gif" >&2; exit 1
  fi
  printf 'Generated %s GIF, video, and poster.\n' "$language"
done
# Publish locally only after both languages encode successfully.
cp work/readme-demo/en/daily/0140.png work/readme-demo/assets/clipori-demo-poster.png
cp work/readme-demo/assets/clipori-demo* docs/assets/
printf 'Updated README and website media in docs/assets/.\n'
