import XCTest
import AppKit
import CliporiCore
@testable import CliporiMac

final class AppModelTests: XCTestCase {
    @MainActor
    func testSearchReflectsEditsAndRapidQueries() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiModel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        var preferences = Preferences(); preferences.language = .chinese
        try await model.store.savePreferences(preferences)
        await model.start()
        model.query = "咖啡"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.displayed.count, 1)
        var record = try XCTUnwrap(model.displayed.first)
        record.body += "\n追加：草莓蛋糕"; record.modifiedAt = Date()
        try await model.save(record)
        model.query = "草莓"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.displayed.first?.id, record.id)
        model.query = "不存在"
        model.query = "代码"
        model.query = "草莓"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.displayed.count, 1)
        XCTAssertEqual(model.displayed.first?.id, record.id)
    }

    @MainActor
    func testClassificationDoesNotAutomaticallyProtectEditedRecords() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CliporiEditor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: true)
        await model.start()
        let editor = EditorModel(record: nil, app: model)
        editor.record.body = "手动添加的记录"
        editor.changed()
        let saved = await editor.flush()
        XCTAssertTrue(saved)
        let persisted = try await model.store.record(id: editor.record.id)
        XCTAssertEqual(persisted?.keepForever, false)
        XCTAssertEqual(persisted?.body, "手动添加的记录")
    }
}
