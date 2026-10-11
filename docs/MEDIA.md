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

The GIF is an **illustrated feature walkthrough**, not a screen recording or a performance measurement. It shows opening the shelf, copying a single item, categorizing a selection, and AI recall. The timing, data, cursor, and AI reply are scripted. Card hover follows the same pointer trajectory throughout these actions, using the app's 6-point lift, 1.018 scale, and enter/leave spring parameters. During a drag, cards settle while the destination category highlights, matching the app.

```sh
# Requires the macOS Swift toolchain and ffmpeg on PATH.
./scripts/make-demo.sh
```

Output:

- `docs/assets/clipori-demo.gif` — 1200 × 720, 20-second loop, 50 fps (2-centisecond frame delays).
- `docs/assets/clipori-demo-poster.png` — a still alternative for readers who prefer no animation.
- The landing page uses smaller H.264 MP4 copies and JPEG posters in English and Chinese, with pause controls and reduced-motion support. See [WEBSITE.md](WEBSITE.md) for conversion and deployment instructions.
- Temporary frames and renderer binaries stay in the ignored `work/readme-demo/` directory.

[`render-demo.swift`](../scripts/render-demo.swift) draws every frame offscreen using AppKit. Its only image input is the repository's cat icon. The backdrop, image card, note text, and AI reply are all fictional and defined in that script. It does **not** read the desktop, screen, clipboard, app database, Keychain, or network, and does not change the running app. This also means translucent surfaces cannot reveal anything from the user's desktop.

To inspect a single moment without encoding the whole animation:

```sh
mkdir -p work/readme-demo
swiftc -O scripts/render-demo.swift -o work/readme-demo/render-demo
work/readme-demo/render-demo work/readme-demo/inspect docs/assets/clipori-icon.png 10.7
```

After updating the artwork or renderer, regenerate the files and review the opening, hover, copying, dragging, and AI scenes before committing. Do not substitute desktop recordings or real clipboard data.

## 中文说明

图标由同一个 Swift 脚本生成，分别提供 macOS 安装图标、iOS 图标和 README 品牌图片。macOS 的 Xcode 构建、Release DMG 和 ZIP 使用同一份 ICNS，包含常用尺寸与 Retina 版本。Clipori 常驻菜单栏，不会持续显示普通 Dock 图标；安装后可在 Finder／应用程序中看到猫咪图标。

GIF 是产品示意动画，展示唤起、单击复制、多选拖分类与 AI 找回。所有操作中的卡片悬停由同一条鼠标轨迹驱动，沿用软件的抬升幅度、缩放比例和进出弹簧参数；拖动期间卡片回落，目标分类高亮，与软件行为一致。卡片、图片、背景、鼠标轨迹、AI 回答均为脚本预设；没有录屏、读取真实历史或调用 AI。它不代表实际模型响应时间或性能测试。脚本同时生成静态预览图。

上面的命令可以重新生成所有素材，临时帧保存在已忽略的 `work/` 中。公开素材只放在 `docs/assets/`；不要混入真实剪贴板、桌面截图或密钥。
