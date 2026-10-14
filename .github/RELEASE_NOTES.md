### 本次更新

**新增**

- 每日备忘录：支持手动记录与 AI 辅助整理当天剪贴板。
- Pin 未完成事项，自动延续到下一天，全部完成后停止延续。
- 支持查看和编辑往期备忘录。

### 安装

需要 macOS 14 或更高版本。M 系列芯片选择 `arm64`，Intel 芯片选择 `x86_64`。打开 DMG，将 Clipori 拖入「应用程序」，或解压 ZIP 后移入。不需要 Xcode，按 `⇧⌘V` 呼出剪贴板。

当前版本采用临时签名，尚未通过 Apple 公证。如系统无法验证开发者，请确认下载来源可信后，按照 [Apple 官方说明](https://support.apple.com/en-us/102445)打开应用。

直接粘贴需要在「系统设置 → 隐私与安全性 → 辅助功能」开启 Clipori。AI 服务在应用设置中配置。这些安装包未启用 iCloud 同步，也不包含 iPhone 安装包。

### 校验安装包

`SHA256SUMS.txt` 包含全部四个安装文件的校验值。在同一文件夹下载所有安装文件与校验文件后，运行以下命令验证；若只下载一个安装文件，其余文件会提示缺失。

```sh
shasum -a 256 -c SHA256SUMS.txt
```

---

### What's new

**Added**

- Daily notes with manual entry and AI-assisted drafts from that day's clipboard.
- Pin unfinished items to carry them into the next day until all tasks are complete.
- View and edit notes from previous days.

### Installation

Requires macOS 14 or later. Choose `arm64` for Apple Silicon (M-series) or `x86_64` for Intel. Open the DMG and drag Clipori into Applications, or unzip the ZIP and move the app there. No Xcode is needed. Press `⇧⌘V` to open the clipboard shelf.

These builds use an ad hoc signature and are not notarized by Apple. If macOS cannot verify the developer, follow [Apple's opening instructions](https://support.apple.com/en-us/102445) only after confirming that you trust the download source.

Enable Clipori in System Settings → Privacy & Security → Accessibility for direct pasting. Configure your AI service in the app's settings. iCloud sync and iPhone distribution are not enabled in these builds.

### Verify the installers

`SHA256SUMS.txt` contains checksums for all four installers. Download the installers and this file into the same folder, then run the command below. If you download only one installer, entries for the other files will be reported as missing.

```sh
shasum -a 256 -c SHA256SUMS.txt
```
