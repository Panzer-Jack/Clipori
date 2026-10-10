# Clipori · Development

[← Back to Clipori](../README.md)

## Build from source

Requires macOS 14+ and Xcode 16+. No third-party runtime dependencies.

```sh
git clone https://github.com/Panzer-Jack/Clipori.git
cd Clipori
./scripts/build-app.sh
open build/Clipori.app
```

Use `./scripts/build-app.sh debug` for a development build. You can also open `Clipori.xcodeproj` in Xcode and run the `CliporiMac` or `CliporiIOS` scheme. The build script produces a `.app` configured to run from the menu bar.

Preview the app with isolated sample data, without capturing the real clipboard or making automatic AI requests:

```sh
open build/Clipori.app --args --demo
```

Quit the app before switching modes. Demo mode uses a separate temporary database and does not add sample content to your real history.

## Development and verification

```sh
swift build
swift test
./scripts/build-app.sh release
```

Run the optional performance benchmark in a local desktop session:

```sh
mkdir -p work/performance
CLIPORI_PERFORMANCE_OUTPUT="$PWD/work/performance/report.json" \
  swift test -c release --filter PerformanceTests
```

It creates 10,000 synthetic records, uses a private pasteboard, and repeatedly opens a test panel. The report covers local search, capture latency, idle CPU, and panel animation timing. AI network latency is excluded. Regular tests and CI skip this benchmark.

Code structure:

- `Sources/CliporiCore`: data models, SQLite storage and search, both AI protocols, and Keychain access.
- `Sources/CliporiMac`: native floating panel, animations, clipboard monitoring, SwiftUI cards, editors, and settings.
- `Tests/CliporiCoreTests`: retention, retrieval, editing and late responses, API requests, error handling, and tests with 10,000 history entries.
- `Sources/CliporiIOS`: iPhone card list, system paste entry point, editor, and settings.
- `CliporiCore` also provides the shared editor, background classification queue, and iCloud sync components.

Build for the iPhone simulator:

```sh
xcodebuild -project Clipori.xcodeproj -scheme CliporiIOS -sdk iphonesimulator \
  -derivedDataPath build/xcode CODE_SIGNING_ALLOWED=NO build
```

The iPhone app saves content through a Paste button and does not read the clipboard in the background. Both apps use local storage by default. iCloud code is integrated but has not been tested between physical devices; developer signing and a CloudKit container must be configured before enabling it. API keys remain on each device.

Current Mac builds use an ad hoc signature. Developer ID signing and notarization still need to be configured for a verified installation experience. Image capture and pasting are currently available locally on Mac; iPhone image support and image sync are planned for a later phase.

## Automated releases

Like [Copiwaifu's release workflow](https://github.com/Panzer-Jack/Copiwaifu/blob/main/.github/workflows/publish-to-release.yml), Clipori publishes when an `app-v*` tag is pushed. First commit and push the application code, scripts, and workflows. From the commit you want to release, run:

```sh
git tag -a app-v0.1.0 -m "Clipori 0.1.0"
git push origin app-v0.1.0
```

GitHub Actions runs the tests on Apple Silicon and Intel, builds both DMG and ZIP installers, verifies checksums, generates release notes, uploads all assets to a draft, and publishes it only after every step succeeds. Versions come from the tag; the app's build number comes from the workflow run number. You do not need to edit the plist for each release.

- Tags such as `app-v0.2.0-beta.1` create prereleases without replacing the latest stable release.
- Retry failures from Actions, or use **Publish release → Run workflow** with an existing tag. Incomplete drafts can be resumed; published releases are never overwritten. Use a new version tag for changes.
- The workflow uses GitHub's built-in `GITHUB_TOKEN`; no personal token or Apple secrets are required for the current ad hoc builds.
- Pushes to `main` and pull requests run CI without publishing. `local-docs/` and `PRD.md` stay ignored, and CI rejects them if they are accidentally tracked.
- This automates GitHub distribution; in-app automatic updates, Apple notarization, and iPhone distribution are not included.

To reproduce the installer build locally (defaults to your Mac's architecture; optionally append `arm64` or `x86_64`):

```sh
./scripts/test-release.sh
./scripts/package-release.sh app-v0.1.0
```

Installers are written to `build/release/`. See [the release workflow](../.github/workflows/publish-to-release.yml) and [the installer script](../scripts/package-release.sh).

