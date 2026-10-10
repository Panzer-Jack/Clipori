## Install / 安装

Requires macOS 14 or later. Choose `arm64` for Apple Silicon (M-series) or `x86_64` for Intel. Open the DMG and drag Clipori into Applications, or unzip the ZIP and move the app there. No Xcode is needed. Press `⇧⌘V` to open the clipboard shelf.

需要 macOS 14 或更高版本。M 系列芯片选择 `arm64`，Intel 芯片选择 `x86_64`。打开 DMG，将 Clipori 拖入「应用程序」，或解压 ZIP 后移入。不需要 Xcode，按 `⇧⌘V` 呼出剪贴板。

These builds use an ad hoc signature and are not notarized by Apple. If macOS cannot verify the developer, follow [Apple's opening instructions](https://support.apple.com/en-us/102445) only after confirming that you trust the download source.

当前版本采用临时签名，尚未通过 Apple 公证。如系统无法验证开发者，请确认下载来源可信后，按照 [Apple 官方说明](https://support.apple.com/en-us/102445)打开应用。

Enable Clipori in System Settings → Privacy & Security → Accessibility for direct pasting. Configure your AI service in the app's settings. iCloud sync and iPhone distribution are not enabled in these builds.

直接粘贴需要在「系统设置 → 隐私与安全性 → 辅助功能」开启 Clipori。AI 服务在应用设置中配置。这些安装包未启用 iCloud 同步，也不包含 iPhone 安装包。

`SHA256SUMS.txt` contains checksums for all four installers. Download the installers and this file into the same folder, then run `shasum -a 256 -c SHA256SUMS.txt`. If you download only one installer, entries for the other files will be reported as missing.

`SHA256SUMS.txt` 包含全部四个安装文件的校验值。在同一文件夹下载所有安装文件与校验文件后，运行 `shasum -a 256 -c SHA256SUMS.txt` 验证；若只下载一个安装文件，其余文件会提示缺失。
