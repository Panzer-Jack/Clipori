<p align="center">
  <img src="docs/assets/clipori-icon.png" alt="Clipori's purple cat app icon" width="112" height="112">
</p>
<h1 align="center">Clipori</h1>
<p align="center"><strong>Copy to remember. Search to rediscover.</strong></p>
<p align="center">A lightweight AI clipboard and notes app for Mac, with a cute design and smooth interactions.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-24232F?logo=apple&amp;logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Native-SwiftUI%20%2B%20AppKit-A98BEF" alt="Native SwiftUI and AppKit">
  <img src="https://img.shields.io/badge/AI-OpenAI%20%7C%20Claude-8DCDB4" alt="OpenAI and Claude compatible">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache--2.0-D5B4EC" alt="Apache 2.0 license"></a>
</p>
<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a><br><br>
  <a href="https://clipori.panzer-jack.cn/">Website</a> ·
  <a href="https://github.com/Panzer-Jack/Clipori/releases"><strong>Download for Mac</strong></a> ·
  <a href="#get-started">Get started</a> ·
  <a href="docs/USAGE.md">Shortcuts &amp; controls</a> ·
  <a href="docs/DEVELOPMENT.md">Build &amp; contribute</a>
</p>

## Demo

See character counts and image sizes, keep repeated text in one card, and bring used cards to the front on your next visit. Classify new entries automatically or sort unclassified history on demand, then plan your day with daily notes.

<p align="center">
  <img src="docs/assets/clipori-demo.gif" alt="Clipori walkthrough: copy, organize, AI recall, character counts and image sizes, text deduplication, recently used cards, new-entry and manual AI classification, and daily notes" width="1200">
</p>

*Illustrated walkthrough with fictional data, scripted AI replies, and compressed date transitions.*

## Features

- Save copied or cut text, links, code, screenshots, and images automatically. Keyboard shortcuts and menu actions both work.
- See character counts on text cards and the stored image size plus pixel dimensions on image cards.
- Reuse the existing card when identical text is copied or cut again, preserving its edits and category.
- Keep recently used cards close: copying or pasting a history card brings it forward the next time the shelf opens; cards stay in place while you browse. Enabled by default and configurable.
- Open with `⇧⌘V`, click to copy, and double-click to paste.
- Drag multiple cards into a category and pin entries.
- Edit records, append notes, or create desktop sticky notes.
- Write daily notes by hand or draft them with AI from that day's clipboard, review cited sources, carry pinned work forward, and revisit previous dates.
- Search with your own OpenAI or Claude compatible service. Optionally auto-classify newly captured entries; classify unclassified history manually in Settings → AI.
- Customize shortcuts, language, retention, and excluded apps.

## Get started

**macOS 14 or later · Apple Silicon and Intel · No Xcode needed for installers**

1. **Download** a DMG or ZIP from [GitHub Releases](https://github.com/Panzer-Jack/Clipori/releases). Choose `arm64` for M-series Macs or `x86_64` for Intel, then drag **Clipori.app** into **Applications**.
2. **Before the first launch**, run this command in Terminal to remove the app's quarantine attribute:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Clipori.app
   ```

3. **Open** Clipori and press **`⇧⌘V`**. It lives in the menu bar. Start copying text or images to build your history.
4. **Enable direct paste**, if you want it: the first double-click or `↩` paste requests Accessibility permission. You can also request it in Settings → General → Quick paste, then enable Clipori in macOS settings. Without permission, the card is copied so you can paste manually with `⌘V`. Copying and history ordering need no permission.
5. **Set up AI** in Settings → AI: choose a protocol, enter your endpoint, model, and API key, then test and save. Clipboard history and keyword search also work without AI.

> Early builds use an ad hoc signature and are not notarized by Apple. If macOS blocks a package you trust, follow [Apple's Open Anyway instructions](https://support.apple.com/en-us/102445). If Releases has no installers yet, [build from source](docs/DEVELOPMENT.md#build-from-source).

### Controls

| Action | Result |
| --- | --- |
| `⇧⌘V` | Show or hide the shelf |
| Hover | Lift and highlight; leave the clipboard unchanged |
| Click | Select only this card and replace the clipboard; keep the shelf open |
| Double-click / `↩` | Copy and paste into the previous app |
| `⌘`-click / `⇧`-click | Toggle multiple selection / select a range for categorizing |
| Drag selected cards to a category | Categorize the whole group |
| Space / `⌘E` | Preview / edit and append |
| `⌘↩` | Search with AI after entering a question |
| Daily notes in the shelf / menu bar | Write, draft with AI, pin ongoing work, and choose previous dates |

Every app shortcut is customizable in Settings → Shortcuts. [See all controls →](docs/USAGE.md)

## Data and settings

- History is stored locally in SQLite; API keys stay in the Keychain. You can pause capture or exclude apps. Standard clipboard privacy markers are respected.
- AI search sends your question and candidate excerpts to your configured service. **AI auto-classification is off by default** and only processes new local captures after it is enabled. Startup, re-enabling it, edits, and repeat copies do not classify your backlog.
- Use **Settings → AI → Classify uncategorized records** to process eligible unclassified history with your saved AI configuration, even when automatic classification is off. It shows progress and can be stopped. Manual categories are preserved; entries without a match remain unclassified.
- Classification uses titles and text, choosing from your existing ordinary categories. Image pixels are never sent: images with text titles or notes can be classified from that text; image-only entries are skipped. There is no OCR or visual classification.
- **AI draft** in daily notes sends excerpts for the selected date and existing items to your service. Review sources, edit, and select suggestions before adding them. There is no automatic daily upload in the background.
- New installations keep history for 30 days. Choose 1 day, 1 week, 1 month, 1 year, or forever. Pinned entries and Pinboards are kept indefinitely. Upgrades preserve your settings; shortening retention requires confirmation.
- The interface uses Chinese when it is the system's preferred language, English otherwise. You can also choose a language in Settings.
- Card icons automatically indicate content type; their colors follow the category.
- Daily notes are stored locally in a separate `daily-notes.sqlite` file, kept indefinitely and excluded from clipboard cleanup. They do not sync through iCloud yet.

<details>
<summary>Storage and image details</summary>

The database lives at `~/Library/Application Support/Clipori/clipori.sqlite`; open its folder from Settings. Capture exclusions cannot identify every sensitive item. Retention uses the original save time; editing, repeat copying, and moving a card forward do not extend it. Deleting a Pinboard keeps its entries and returns them to the normal retention policy.

Character counts exclude whitespace and line breaks, but include punctuation and emoji. Text and links are deduplicated only when their full text matches exactly; differences in case, spaces, or line breaks remain separate. Images are not deduplicated, and existing duplicate history is not bulk-cleaned. External repeat copies or cuts move the existing card forward when “Move to front after use” is enabled.

PNG, TIFF, and JPEG images are supported. The size label reflects the locally stored PNG, which can differ from the original file size. Use `⌃⇧⌘4` to copy a screenshot selection; screenshots saved only as files are not automatically captured. Clipori preserves pixel dimensions and transparency, stores small thumbnails for browsing, and copies PNG/TIFF for compatible apps. Add titles or notes to make images searchable. Images above 128 MB or 80 megapixels are rejected with a message.

</details>

## Project status

| Available now on Mac | Next steps |
| --- | --- |
| Clipboard history, screenshots, editing, categories, multi-select drag, desktop notes | iPhone image support and image sync |
| Daily notes, AI drafts, pinned carry-over, and previous dates | iCloud signing and testing between physical devices |
| AI recall, optional classification, custom shortcuts, Chinese/English, retention | Developer ID signing, notarization, and in-app updates |

The repository also contains a **local iPhone companion** and shared iCloud components. Cross-device sync is not yet ready for daily use; both apps use local storage by default. There is no public iPhone installer yet. Multi-selection currently supports categorizing, not batch pasting.

## Build & contribute

```sh
git clone https://github.com/Panzer-Jack/Clipori.git
cd Clipori
./scripts/build-app.sh
open build/Clipori.app
```

Requires macOS 14+ and Xcode 16+. Built with SwiftUI, AppKit, and SQLite, without third-party runtime dependencies.

- [Development, tests, performance benchmarks, and automated releases](docs/DEVELOPMENT.md)
- [Reproduce the icon and the privacy-safe demo](docs/MEDIA.md)
- [Report a bug or suggest an idea](https://github.com/Panzer-Jack/Clipori/issues)

## License

[Apache-2.0](LICENSE). The cat app artwork and illustrated demo are generated from the source scripts in this repository.

Inspired by [Paste](https://pasteapp.io/).
