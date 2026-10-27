### 本次更新

**新增**

- 在「设置 → 通用 → 外观」下方新增「背景不透明度」滑杆，默认 85%，可调至 100% 完全不透明，减少底下窗口的文字和图片干扰。点击「保存设置」后生效，重启后保留选择；文字和按钮保持清晰。系统开启「降低透明度」时，优先使用不透明背景。

### 安装

需要 macOS 14 或更高版本。M 系列芯片选择 `arm64`，Intel 芯片选择 `x86_64`。打开 DMG，将 Clipori 拖入「应用程序」，或解压 ZIP 后移入。不需要 Xcode，按 `⇧⌘V` 呼出剪贴板。

当前版本采用临时签名，尚未通过 Apple 公证。如系统无法验证开发者，请确认下载来源可信后，按照 [Apple 官方说明](https://support.apple.com/en-us/102445)打开应用。

直接粘贴会主动申请辅助功能权限，也可在「设置 → 通用 → 快捷粘贴」中申请，再到系统设置开启 Clipori。普通复制与历史排序无需此权限。AI 服务在应用设置中配置。这些安装包未启用 iCloud 同步，也不包含 iPhone 安装包。

### 校验安装包

`SHA256SUMS.txt` 包含全部四个安装文件的校验值。在同一文件夹下载所有安装文件与校验文件后，运行以下命令验证；若只下载一个安装文件，其余文件会提示缺失。

```sh
shasum -a 256 -c SHA256SUMS.txt
```

---

### What's new

**Added**

- A “Background opacity” slider below Appearance in Settings → General defaults to 85% and supports a fully opaque background at 100%, reducing distractions from text and images in windows behind the shelf. Changes apply after clicking “Save settings” and persist across restarts; text and buttons stay clear. When Reduce Transparency is enabled in macOS, the shelf uses an opaque background regardless of this setting.

### Installation

Requires macOS 14 or later. Choose `arm64` for Apple Silicon (M-series) or `x86_64` for Intel. Open the DMG and drag Clipori into Applications, or unzip the ZIP and move the app there. No Xcode is needed. Press `⇧⌘V` to open the clipboard shelf.

These builds use an ad hoc signature and are not notarized by Apple. If macOS cannot verify the developer, follow [Apple's opening instructions](https://support.apple.com/en-us/102445) only after confirming that you trust the download source.

Direct paste requests Accessibility permission. You can also request it in Settings → General → Quick paste, then enable Clipori in macOS settings. Copying and history ordering do not require this permission. Configure your AI service in the app's settings. iCloud sync and iPhone distribution are not enabled in these builds.

### Verify the installers

`SHA256SUMS.txt` contains checksums for all four installers. Download the installers and this file into the same folder, then run the command below. If you download only one installer, entries for the other files will be reported as missing.

```sh
shasum -a 256 -c SHA256SUMS.txt
```
