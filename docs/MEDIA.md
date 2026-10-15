# Clipori · Brand & demo assets

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## One icon, every build

The purple cat is drawn by [`scripts/make-icon.swift`](../scripts/make-icon.swift). It exports:

| Asset | Used by |
| --- | --- |
| `Resources/AppIcon.icns` | Finder, Applications, native app dialogs, both the macOS Xcode target and the DMG/ZIP build |
| `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | The iOS AppIcon asset catalog; opaque 1024 × 1024 |
| `docs/assets/clipori-icon.png` | Both READMEs and the illustrated demo; transparent 512 × 512 |

Regenerate all three from the repository root on macOS:

```sh
swift scripts/make-icon.swift \
  Resources/AppIcon.icns \
  Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  docs/assets/clipori-icon.png
```

The ICNS includes 16, 32, 128, 256, and 512 point representations at 1× and 2×. Both Mac plists explicitly reference `AppIcon.icns`. Release builds copy this checked-in asset instead of redrawing a different copy. The application also loads it for its runtime app icon. Clipori is a menu bar app, so it does not keep a normal Dock tile open.

The menu bar uses a separate 18-point monochrome cat drawn by [`MenuBarIcon.swift`](../Sources/CliporiMac/MenuBarIcon.swift). It is an AppKit template image, so macOS applies the correct tint for light, dark, and selected menu bar states. The vector drawing renders at the screen's native scale and is compiled into the app, with no extra image resource to package.

## Reproduce the demo

The GIF is an **illustrated feature walkthrough**, not a screen recording or a performance measurement. It shows opening the shelf, copying a single item, categorizing a selection, AI recall, character counts and image sizes, exact-text deduplication, recency on reopening, new-capture versus manual history classification, and then daily notes: manual entry, reviewing and editing an AI suggestion, pinning unfinished work, completing it the next day, and revisiting a previous date. The timing, data, cursor, and AI reply are scripted. Card hover follows the same pointer trajectory throughout these actions, using the app's 6-point lift, 1.018 scale, and enter/leave spring parameters. During a drag, cards settle while the destination category highlights, matching the app.

```sh
# Requires the macOS Swift toolchain and ffmpeg on PATH.
./scripts/make-demo.sh
```

Output:

- `docs/assets/clipori-demo.gif` (English) and `clipori-demo-zh.gif` (Chinese) — 1200 × 800, 78-second loop. The first 20 seconds retain the shelf animation at 50 fps; the next 28 seconds show metadata, deduplication, ordering, and AI classification at 10 fps; the final 30 seconds show daily notes at 10 fps. Both later chapters hold each frame within the same 50 fps timeline.
- `docs/assets/clipori-demo-poster.png` — a still of text counts and image metadata at 22 seconds for readers who prefer no animation.
- The same command also generates `clipori-demo-en.mp4`, `clipori-demo-zh.mp4`, and `clipori-demo-poster-en.jpg` / `clipori-demo-poster-zh.jpg` for the landing page. GIFs and videos use the same source frames; each language has a matching metadata poster. See [WEBSITE.md](WEBSITE.md) for preview and deployment instructions.
- Temporary frames and renderer binaries stay in the ignored `work/readme-demo/` directory.

[`render-demo.swift`](../scripts/render-demo.swift) and [`render-daily-demo.swift`](../scripts/render-daily-demo.swift) draw the shelf, history (the `history` argument), and daily-notes scenes offscreen using AppKit. `make-demo.sh` combines them into one complete walkthrough per language. Each README embeds its matching language. The script stages all outputs in `work/readme-demo/assets/`, checks the 25 MiB GIF limit, and updates the public assets only after both languages finish encoding. Its only image input is the repository's cat icon. The backdrop, image card, note text, and AI reply are all fictional and defined in the renderers. It does **not** read the desktop, screen, clipboard, app database, Keychain, or network, and does not change the running app. This also means translucent surfaces cannot reveal anything from the user's desktop.

To inspect a single moment without encoding the whole animation:

```sh
mkdir -p work/readme-demo
swiftc -O scripts/render-demo.swift -o work/readme-demo/render-demo
work/readme-demo/render-demo work/readme-demo/inspect docs/assets/clipori-icon.png 10.7 zh
# New history chapter: inspect the classification result at its local 26-second mark.
work/readme-demo/render-demo work/readme-demo/inspect-history docs/assets/clipori-icon.png 26 zh history
```

After updating the artwork or renderers, regenerate the files and review the opening, hover, copying, dragging, AI, and daily-notes scenes before committing. For the history chapter, inspect the combined timeline at 22, 29, 33.5, 34.8, 36, 38.5, 41, 44.5, and 46 seconds: counts, unchanged record count after a repeat cut, stable cards after copying, closing/reopening, and classification only after the relevant trigger. For daily notes, inspect 51.5, 56, 62, 67, 70, and 75 seconds. Check sources, completion state, selected dates, and the unchanged previous-day snapshot. Date transitions are explicitly labeled and compressed; the demo does not depict an app control that advances time or actual AI response latency. Do not substitute desktop recordings or real clipboard data.

## 中文说明

图标由同一个 Swift 脚本生成，分别提供 macOS 安装图标、iOS 图标和 README 品牌图片。macOS 的 Xcode 构建、Release DMG 和 ZIP 使用同一份 ICNS，包含常用尺寸与 Retina 版本。Clipori 常驻菜单栏，不会持续显示普通 Dock 图标；安装后可在 Finder／应用程序中看到猫咪图标。

GIF 是一段完整的产品示意动画：先展示唤起、单击复制、多选拖分类与 AI 找回，接着展示字数与图片大小、精确文本去重、复制后保持原位且下次打开前移、新收录自动分类与历史手动分类，最后展示每日备忘录的手动记录、AI 建议审阅、Pin 跨天保留、全部完成后停止延续、往期回看。中英文 README 各自展示对应语言的总演示，不单独展示每日备忘录 GIF。官网的中英文 GIF、MP4 和封面由同一条命令一起生成，总时长 78 秒，封面使用第 22 秒的字数与图片大小画面。所有操作中的卡片悬停由同一条鼠标轨迹驱动，沿用软件的抬升幅度、缩放比例和进出弹簧参数；拖动期间卡片回落，目标分类高亮，与软件行为一致。卡片、图片、背景、鼠标轨迹、AI 回答均为脚本预设；没有录屏、读取真实历史或调用 AI。它不代表实际模型响应时间或性能测试。跨天过程已压缩，画面标注了日期推进；脚本同时生成静态预览图。

上面的命令可以重新生成所有素材，临时帧保存在已忽略的 `work/` 中。公开素材只放在 `docs/assets/`；不要混入真实剪贴板、桌面截图或密钥。
