# Clipori · 开发

[← 返回 Clipori](../README.zh-CN.md)

## 从源码构建

需要 macOS 14+、Xcode 16+。项目没有第三方运行时依赖。

```sh
git clone https://github.com/Panzer-Jack/Clipori.git
cd Clipori
./scripts/build-app.sh
open build/Clipori.app
```

开发时可使用 `./scripts/build-app.sh debug`。也可以在 Xcode 中打开 `Clipori.xcodeproj`，选择 `CliporiMac` 或 `CliporiIOS` 运行。打包脚本会生成带菜单栏应用配置的 `.app`。

查看隔离的示例界面（不记录真实剪贴板、不自动调用 AI）：

```sh
open build/Clipori.app --args --demo
```

若应用已运行，先退出再切换模式。示例模式使用独立的临时数据库，不会给真实历史添加演示内容。

## 开发与验证

```sh
swift build
swift test
./scripts/build-app.sh release
```

在本机桌面会话中运行可选性能基准：

```sh
mkdir -p work/performance
CLIPORI_PERFORMANCE_OUTPUT="$PWD/work/performance/report.json" \
  swift test -c release --filter PerformanceTests
```

测试生成 1 万条示例记录，使用私有剪贴板，并反复弹出测试面板。报告包含本地搜索、采集延迟、空闲 CPU 和面板动画时间，不包含 AI 网络耗时。普通测试与 CI 自动跳过此基准。

代码结构：

- `Sources/CliporiCore`：数据模型、SQLite 存储与检索、双协议 AI、钥匙串。
- `Sources/CliporiMac`：原生浮动面板、动效、剪贴板监听、SwiftUI 卡片与编辑设置界面。
- `Tests/CliporiCoreTests`：保留策略、检索、编辑与迟到响应、协议请求、错误处理和万条历史测试。
- `Sources/CliporiIOS`：iPhone 卡片列表、系统粘贴入口、编辑器和设置。
- `CliporiCore` 同时提供共享编辑器、后台分类队列和 iCloud 同步组件。

运行 iPhone 模拟器构建：

```sh
xcodebuild -project Clipori.xcodeproj -scheme CliporiIOS -sdk iphonesimulator \
  -derivedDataPath build/xcode CODE_SIGNING_ALLOWED=NO build
```

iPhone 通过“粘贴”按钮保存内容，不在后台读取系统剪贴板。两端默认本地使用，iCloud 代码已接入但尚未真机联调；需要配置开发者签名与容器后才能启用。API Key 只留在各自设备。

当前 Mac 构建使用临时签名，后续仍需配置 Developer ID 签名和公证，以提供通过系统验证的安装体验。图片收录与回粘已支持 Mac 本地使用；iPhone 图片支持和图片同步安排在后续阶段。

## 自动发布

参考 [Copiwaifu 的发布流程](https://github.com/Panzer-Jack/Copiwaifu/blob/main/.github/workflows/publish-to-release.yml)，推送 `app-v*` 标签即可发布 Clipori。先提交并推送应用代码、脚本和工作流，再在需要发布的提交上执行：

```sh
git tag -a app-v0.3.0 -m "Clipori 0.3.0"
git push origin app-v0.3.0
```

GitHub Actions 会在 Apple Silicon 和 Intel 上运行测试，构建两套 DMG、ZIP，验证校验值，自动生成更新说明，并将所有安装包上传到草稿。全部成功后才公开 Release。应用版本取自标签，构建号取自工作流运行编号，每次发布不必修改 plist。

- `app-v0.2.0-beta.1` 这类标签会发布为预发布版本，不替换最新稳定版。
- 失败后可在 Actions 重试，或通过 **Publish release → Run workflow** 输入已有标签重新运行。未完成的草稿可继续上传；已公开版本不会被覆盖，内容变更应使用新版本标签。
- 使用 GitHub 内置的 `GITHUB_TOKEN`，当前临时签名构建无需配置个人 Token 或 Apple 密钥。
- 推送 `main` 和提交 PR 只运行 CI，不发布。`local-docs/` 与 `PRD.md` 继续被忽略；若被意外加入 Git 跟踪，CI 会报错。
- 该流程负责 GitHub 构建分发，暂不包含应用内自动更新、Apple 公证或 iPhone 分发。

本地复现安装包构建（默认当前 Mac 架构，也可在命令末尾追加 `arm64` 或 `x86_64`）：

```sh
./scripts/test-release.sh
./scripts/package-release.sh app-v0.1.0
```

安装包输出到 `build/release/`。实现见 [发布工作流](../.github/workflows/publish-to-release.yml)和[打包脚本](../scripts/package-release.sh)。

