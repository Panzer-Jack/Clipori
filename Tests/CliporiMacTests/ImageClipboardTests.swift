import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
import CliporiCore
@testable import CliporiMac

@MainActor
final class ImageClipboardTests: XCTestCase {
    override func setUpWithError() throws { _ = NSApplication.shared }
    func testPNGAndTIFFAndJPEGCaptureThumbnailRoundTripAndNoDuplicateOnCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiImage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: false)
        await model.start()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(model: model, pasteboard: board, source: { .init(name: "Screenshot test", bundleID: "test.image", processID: nil) })
        let png = try fixture(type: .png, width: 960, height: 600)
        let tiff = try fixture(type: .tiff, width: 480, height: 300)
        let jpeg = try fixture(type: .jpeg, width: 240, height: 150)
        for (index, item) in [(NSPasteboard.PasteboardType.png, png), (.tiff, tiff), (.init("public.jpeg"), jpeg)].enumerated() {
            board.clearContents(); board.setData(item.1, forType: item.0)
            board.setString("Image alt text must not replace the pixels", forType: .string)
            monitor.poll(); monitor.poll()
            for _ in 0..<100 {
                if model.captureCount == index + 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(model.captureCount, index + 1)
        }
        let records = try await model.store.list()
        XCTAssertEqual(records.count, 3)
        XCTAssertTrue(records.allSatisfy { $0.kind == .image && $0.body.isEmpty && $0.sourceBundleID == "test.image" })
        let first = try XCTUnwrap(records.first { $0.imageSize?.width == 960 })
        let attachment = try XCTUnwrap(first.attachment)
        let stored = try await model.store.imageData(attachment: attachment)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(try XCTUnwrap(stored) as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 960); XCTAssertEqual(image.height, 600)
        XCTAssertNotEqual(image.alphaInfo, .none, "Preserve transparency")
        let thumb = try await model.store.imageData(attachment: attachment, thumbnail: true)
        let thumbSource = try XCTUnwrap(CGImageSourceCreateWithData(try XCTUnwrap(thumb) as CFData, nil))
        let thumbImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(thumbSource, 0, nil))
        XCTAssertLessThanOrEqual(max(thumbImage.width, thumbImage.height), 512)
        let copied = await monitor.copy(first)
        XCTAssertTrue(copied)
        XCTAssertEqual(board.data(forType: .png), stored)
        XCTAssertNotNil(board.data(forType: .tiff))
        let pastedImage = try XCTUnwrap(NSImage(pasteboard: board))
        XCTAssertEqual(pastedImage.representations.first?.pixelsWide, 960)
        XCTAssertNil(board.string(forType: .string), "Copy pixels, not a path or a note")
        XCTAssertEqual(board.pasteboardItems?.count, 1, "PNG and TIFF are formats of the same item")
        let copiedText = await monitor.copy(Memory(body: "text after image"))
        XCTAssertTrue(copiedText)
        XCTAssertEqual(board.pasteboardItems?.count, 1)
        XCTAssertEqual(board.string(forType: .string), "text after image")
        XCTAssertNil(board.data(forType: .png))
        XCTAssertNil(board.data(forType: .tiff))
        let copiedImageAgain = await monitor.copy(first)
        XCTAssertTrue(copiedImageAgain)
        XCTAssertEqual(board.pasteboardItems?.count, 1)
        XCTAssertEqual(board.data(forType: .png), stored)
        XCTAssertNil(board.string(forType: .string))
        monitor.poll()
        try await Task.sleep(for: .milliseconds(60))
        let count = try await model.store.count()
        XCTAssertEqual(count, 3)
        let reopened = try MemoryStore(url: directory.appendingPathComponent("clipori.sqlite"))
        let reopenedData = try await reopened.imageData(attachment: attachment)
        XCTAssertEqual(reopenedData, stored)
    }

    func testImagesRespectPrivacyWithoutDroppingCapturesWhenCliporiBecomesForeground() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiImagePrivacy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: false)
        await model.start()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var ownProcess = false
        let monitor = ClipboardMonitor(model: model, pasteboard: board, source: { .init(name: "Private", bundleID: "test.private", processID: ownProcess ? ProcessInfo.processInfo.processIdentifier : nil) })
        let png = try fixture(type: .png)
        func put() { board.clearContents(); board.setData(png, forType: .png) }
        model.preferences.capturePaused = true; put(); monitor.poll()
        model.preferences.capturePaused = false; model.preferences.ignoredApps = ["test.private"]; put(); monitor.poll()
        model.preferences.ignoredApps = []
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            put(); board.setString("1", forType: .init(marker)); monitor.poll()
        }
        try await Task.sleep(for: .milliseconds(100))
        let count = try await model.store.count()
        XCTAssertEqual(count, 0)
        ownProcess = true; put(); monitor.poll()
        try await Task.sleep(for: .milliseconds(100))
        let captured = try await model.store.list()
        XCTAssertEqual(captured.count, 1)
        let selfCopied = await monitor.copy(try XCTUnwrap(captured.first))
        XCTAssertTrue(selfCopied)
        monitor.poll()
        try await Task.sleep(for: .milliseconds(60))
        let afterCopy = try await model.store.count()
        XCTAssertEqual(afterCopy, 1, "Suppress actual card copies, not all clipboard updates while our app is frontmost")
        var missing = Memory(body: "", kind: .image); missing.attachment = UUID().uuidString
        board.clearContents(); board.setString("keep existing clipboard", forType: .string)
        let copied = await monitor.copy(missing)
        XCTAssertFalse(copied)
        XCTAssertEqual(board.string(forType: .string), "keep existing clipboard")
    }

    func testCorruptImagesAreRejectedWithoutSavingAPhantomRecord() async throws {
        do {
            _ = try await ClipboardImageProcessor.shared.prepare(Data("not an image".utf8))
            XCTFail("Invalid pixels must fail before saving")
        } catch { XCTAssertTrue(error is ClipboardImageError) }
    }

    private func fixture(type: UTType, width: Int = 160, height: Int = 100) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 0.7))
        context.fill(CGRect(x: 10, y: 10, width: width - 20, height: height - 20))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
