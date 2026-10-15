import AppKit
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testCutIsCapturedWhenCliporiIsForegroundAndDataArrivesAfterDeclaration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        model.ready = true; model.isVisible = true
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(model: model, pasteboard: board, source: {
            .init(name: "Clipori", bundleID: "app.clipori", processID: ProcessInfo.processInfo.processIdentifier)
        })
        // Both Cmd-X and menu Cut reach this same NSPasteboard path; no key event is needed.
        board.declareTypes([.string], owner: nil)
        let declared = board.changeCount
        monitor.poll()
        board.setString("text cut via menu", forType: .string)
        XCTAssertEqual(board.changeCount, declared)
        monitor.poll()
        try await Task.sleep(for: .milliseconds(80))
        let records = try await model.store.list()
        XCTAssertEqual(records.map(\.body), ["text cut via menu"])
        XCTAssertEqual(model.memories, records, "A cut must be visible immediately even when the shelf was already open")
        let copied = await monitor.copy(try XCTUnwrap(records.first))
        XCTAssertTrue(copied)
        monitor.poll()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(model.captureCount, 1, "Card copies must still suppress self-capture")
    }

    func testCopyReplacesEveryPreviousItemAndFormat() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(model: model, pasteboard: board)
        let oldItems = [NSPasteboardItem(), NSPasteboardItem()]
        for item in oldItems {
            item.setString("old content", forType: .string)
            item.setData(Data("old rich text".utf8), forType: .rtf)
        }
        board.clearContents(); board.writeObjects(oldItems)
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        for body in ["first card", "second card", "third card"] {
            let copied = await monitor.copy(Memory(body: body))
            XCTAssertTrue(copied)
            XCTAssertEqual(board.pasteboardItems?.count, 1)
            XCTAssertEqual(board.string(forType: .string), body)
            XCTAssertNil(board.data(forType: .rtf))
        }
    }

    func testLateImageLoadCannotOverwriteTheLatestTextOrItsFeedback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        // Control completion order instead of relying on file size or a timing delay.
        for result: Result<Data?, Error> in [.success(Data()), .failure(ClipboardImageError.missing)] {
            let loading = expectation(description: "Image copy is waiting for storage")
            var pending: CheckedContinuation<Data?, Error>?
            let monitor = ClipboardMonitor(model: model, pasteboard: board, loadImage: { _ in
                try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    loading.fulfill()
                }
            })
            var image = Memory(body: "", kind: .image)
            image.attachment = UUID().uuidString
            let earlierCopy = Task { await monitor.copy(image) }
            await fulfillment(of: [loading], timeout: 2)
            let copiedText = await monitor.copy(Memory(body: "last clicked card"))
            XCTAssertTrue(copiedText)
            model.notice = "latest feedback"
            try XCTUnwrap(pending).resume(with: result)
            let copiedImage = await earlierCopy.value
            XCTAssertFalse(copiedImage)
            XCTAssertEqual(board.string(forType: .string), "last clicked card")
            XCTAssertEqual(board.pasteboardItems?.count, 1)
            XCTAssertNil(board.data(forType: .png))
            XCTAssertEqual(model.notice, "latest feedback")
        }
    }

    func testCapturesCopyOnlyOnceAndRespectsPausePrivacyAndIgnoredApps() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: false)
        await model.start()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(model: model, pasteboard: board, source: { .init(name: "测试编辑器", bundleID: "test.editor", processID: nil) })
        func copy(_ value: String) { board.clearContents(); board.setString(value, forType: .string); monitor.poll() }
        copy("第一次复制的备忘")
        try await Task.sleep(for: .milliseconds(80))
        let first = try await model.store.list()
        XCTAssertEqual(first.count, 1); XCTAssertEqual(first.first?.sourceBundleID, "test.editor")
        monitor.poll()
        await monitor.copy(first[0]); monitor.poll()
        model.preferences.capturePaused = true; copy("暂停期间不保存")
        model.preferences.capturePaused = false
        model.preferences.ignoredApps = ["test.editor"]; copy("忽略应用不保存")
        model.preferences.ignoredApps = []
        board.clearContents(); board.setString("隐私内容", forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")); monitor.poll()
        try await Task.sleep(for: .milliseconds(80))
        let final = try await model.store.list()
        XCTAssertEqual(final.map(\.body), ["第一次复制的备忘"])
    }
}
