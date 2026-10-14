# Clipori website

The bilingual product landing page lives in `index.html`, `site.css`, and `site.js`. Scroll motion and the feature carousel are in `motion.css` and `motion.js`. It uses plain HTML, CSS, and JavaScript, with no runtime dependencies or third-party requests. Layout uses Flexbox and margins, without CSS Grid or gap.

## Preview and publish

Serve `docs/` with any static HTTP server. Language defaults to the browser's preferred language (Chinese for `zh`, English otherwise), with a remembered manual choice. `?lang=en` and `?lang=zh` override the preference for shareable links. Download buttons open the project's latest GitHub Release.

```sh
bash scripts/build-site.sh
```

The export contains only the website and selected public assets in `build/site/`. Markdown documentation, app data, and `local-docs/` are not included.

GitHub Pages uses `.github/workflows/pages.yml`. In repository Settings → Pages, choose **GitHub Actions** as the source. Push website changes to `main` (or run **Publish website** manually) to deploy:

https://panzer-jack.github.io/Clipori/

No app release or version tag is needed for website updates. To use a custom domain later, configure it in GitHub Pages and update the canonical/Open Graph URLs in `index.html` and `site.js`.

## Media

English and Chinese GIFs, H.264 MP4s with fast-start metadata, and JPEG posters are generated together by `scripts/make-demo.sh`. Both languages use a 1200 × 800, 50-second walkthrough: 20 seconds of clipboard features followed by 30 seconds of daily notes. Video and GIF use the same source frames, and posters show the pinned daily note at 34 seconds. They loop silently without native video controls; a discreet play/pause button remains accessible. GIF links remain available. Playback pauses when scrolled offscreen or the tab is hidden, then resumes on return unless the visitor paused it. Reduced-motion preferences disable automatic playback.

Keep exported GIFs below the host's 25 MiB per-file limit. The generator checks both GIF sizes before updating public files. Recheck the durations, language, and posters after changes; the video element uses the same 1200 × 800 dimensions in both languages.

The six independent feature demos use HTML/CSS animation with fictional data: capture, paste, multi-select categorization, AI recall, optional AI classification, and editing or appending to saved memories. Switch with tabs, previous/next buttons, arrow keys, or a horizontal swipe. Only the active, visible scene animates. A pause button and reduced-motion static compositions are provided. Scroll effects use IntersectionObserver and a single animation frame per scroll update; they do not hijack scrolling.

```sh
# Regenerate both languages: GIFs, MP4s, and posters.
./scripts/make-demo.sh
# Export the updated assets with the website.
bash scripts/build-site.sh
```

The website identifies this media as an illustrated walkthrough, not a live screen recording or an AI speed benchmark. See [MEDIA.md](MEDIA.md) for the source and privacy boundaries. No testimonials, performance claims, tracking scripts, or unsupported sync promises are included.

## 中文说明

官网使用原生 HTML / CSS / JavaScript，无需安装依赖。中英文文案在 `site.js`，默认跟随浏览器语言，手动切换会保存。可用 `?lang=zh` / `?lang=en` 分享指定语言。

`bash scripts/build-site.sh` 导出公开页面。GitHub Pages 来源选择 GitHub Actions 后，推送官网相关文件到 `main` 即可自动发布；也可手动运行 **Publish website**。官网更新不会触发应用 Release。安装命令的复制按钮只复制文字，不在访问者电脑上执行命令。

更新演示时运行 `./scripts/make-demo.sh`，一次生成中英文总 GIF、官网 MP4 和封面，再运行 `bash scripts/build-site.sh` 检查导出。两种语言均为 1200 × 800、50 秒，包含每日备忘录；不要只替换 README 引用的 GIF。
