### 本次更新

**新增**

- 文本卡片显示字数，计入标点与 emoji，不计空白和换行；图片卡片显示本机保存的 PNG 大小与像素尺寸。
- 相同文本或链接重复复制、剪切时复用原记录，保留标题、分类、固定状态与首次收录时间。大小写、空格或换行不同仍视为不同内容；图片不去重，也不会批量清理已有重复记录。
- 「使用后移到最前」默认开启，可在设置中关闭。外部重复复制或剪切会让原记录前移；复制或粘贴历史卡片后，当前面板位置不变，下次打开时排到最前。排序无需辅助功能权限，也不会延长记录保留期限。
- 新增「分类未分类记录」按钮，在「设置 → AI」手动处理历史未分类内容，支持查看进度与停止，无需开启自动分类。

**优化**

- AI 自动分类默认关闭，开启后仅处理新收录的本地记录；启动、编辑、同步、重复复制或重新开启开关都不会补跑历史。自动与手动批量分类均保留手动分类，没有合适分类的记录保持未分类。
- AI 分类只使用标题和文字内容，从已有普通分类中选择。带文字标题或备注的图片可按文字分类，纯图片跳过；不发送图片像素，不支持 OCR 或画面识别。
- 首次直接粘贴时主动申请辅助功能权限，也可在设置中手动申请；拒绝后不反复自动弹出。未授权时先复制内容，可切回目标应用按 `⌘V` 粘贴。
- 通用设置拆分为「历史排序」与「快捷粘贴」，精简权限说明；移除应用内「减少动效」开关，继续遵循系统的减弱动态效果设置。
- 更新中英文 README、官网说明及 GIF、视频和封面，演示本次新增交互。

**修复**

- 剪切与复制使用相同的收录规则，覆盖 `⌘X`、菜单剪切及应用切换场景，改善剪贴板延迟提供内容时的收录。
- 修复本地数据库字段数量不匹配导致的保存失败，兼容旧版记录及此前的排序字段迁移。

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

- Text cards show character counts, including punctuation and emoji but excluding whitespace and line breaks. Image cards show the locally stored PNG size and pixel dimensions.
- Repeated copies or cuts of identical text or links reuse the existing record, preserving its title, category, pin status, and original capture date. Case, spaces, and line breaks remain significant. Images are not deduplicated, and existing duplicates are not bulk-cleaned.
- “Move to front after use” is enabled by default and can be disabled in settings. Repeated external copies or cuts promote the existing record. Copying or pasting a history card keeps its current position and brings it forward the next time the shelf opens. Ordering needs no Accessibility permission and does not extend retention.
- A “Classify uncategorized records” button in Settings → AI processes eligible unclassified history on demand, with progress and a stop control. Automatic classification does not need to be enabled.

**Improved**

- AI auto-classification is off by default and only processes new local captures while enabled. Launching, editing, syncing, repeat copies, or re-enabling it never scans the backlog. Both automatic and manual batch classification preserve manual categories; unmatched entries remain unclassified.
- Classification uses titles and text to choose from existing ordinary categories. Images with text titles or notes can be classified from that text; image-only records are skipped. Image pixels are never sent, and OCR or visual recognition is not supported.
- The first direct paste requests Accessibility permission, with a manual request available in settings. Declining stops repeated automatic prompts. Without access, the content is copied so it can be pasted manually with `⌘V` in the destination app.
- General settings now separate “History order” and “Quick paste,” with clearer permission guidance. The in-app Reduce motion toggle is removed; the system's reduced-motion preference is still respected.
- Updated the English and Chinese READMEs, website copy, GIFs, videos, and posters to demonstrate the new interactions.

**Fixed**

- Cut and Copy now follow the same capture rules, covering `⌘X`, menu actions, and app switching, with more reliable capture when clipboard data becomes available later.
- Fixed save failures caused by a local database column-count mismatch, with compatibility for older records and migration of the earlier ordering field.

### Installation

Requires macOS 14 or later. Choose `arm64` for Apple Silicon (M-series) or `x86_64` for Intel. Open the DMG and drag Clipori into Applications, or unzip the ZIP and move the app there. No Xcode is needed. Press `⇧⌘V` to open the clipboard shelf.

These builds use an ad hoc signature and are not notarized by Apple. If macOS cannot verify the developer, follow [Apple's opening instructions](https://support.apple.com/en-us/102445) only after confirming that you trust the download source.

Direct paste requests Accessibility permission. You can also request it in Settings → General → Quick paste, then enable Clipori in macOS settings. Copying and history ordering do not require this permission. Configure your AI service in the app's settings. iCloud sync and iPhone distribution are not enabled in these builds.

### Verify the installers

`SHA256SUMS.txt` contains checksums for all four installers. Download the installers and this file into the same folder, then run the command below. If you download only one installer, entries for the other files will be reported as missing.

```sh
shasum -a 256 -c SHA256SUMS.txt
```
