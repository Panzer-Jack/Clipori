import XCTest
@testable import CliporiCore

final class PreferencesTests: XCTestCase {
    func testShelfOpacityDefaultsAndLegacyPreferences() throws {
        XCTAssertEqual(Preferences().shelfBackgroundOpacity, 0.85)
        for json in [#"{}"#, #"{"appearance":"dark","shelfBackgroundOpacity":null}"#] {
            let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            XCTAssertEqual(preferences.shelfBackgroundOpacity, 0.85)
        }
    }

    func testShelfOpacityRoundTripAndBounds() throws {
        for value in [0.0, 0.35, 0.85, 1.0] {
            var preferences = Preferences()
            preferences.shelfBackgroundOpacity = value
            let reopened = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(reopened.shelfBackgroundOpacity, value)
        }
        for (value, expected) in [(-0.5, 0.0), (1.5, 1.0)] {
            let json = "{\"shelfBackgroundOpacity\":\(value)}"
            let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.shelfBackgroundOpacity, expected)
            var preferences = Preferences()
            preferences.shelfBackgroundOpacity = value
            XCTAssertEqual(preferences.shelfBackgroundOpacity, expected)
        }
        for value in [Double.nan, .infinity, -.infinity] {
            var preferences = Preferences()
            preferences.shelfBackgroundOpacity = value
            XCTAssertEqual(preferences.shelfBackgroundOpacity, 0.85)
            XCTAssertNoThrow(try JSONEncoder().encode(preferences))
        }
    }

    func testLanguageFollowsPrimarySystemLanguageAndExplicitOverride() {
        for identifier in ["zh", "zh-Hans-CN", "zh-Hant-TW", "zh-HK"] {
            XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: [identifier]), .chinese)
        }
        for languages in [["en-US", "zh-CN"], ["ja-JP", "zh-Hant"], ["fr"], []] {
            XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: languages), .english)
        }
        XCTAssertEqual(AppLanguage.chinese.resolved(preferredLanguages: ["en"]), .chinese)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["zh"]), .english)
    }

    func testLanguageChangesBuiltInLabelsWithoutChangingUserContent() {
        let previous = L10n.language; defer { L10n.language = previous }
        L10n.language = .english
        XCTAssertEqual(MemoryCategory.defaults[0].displayName, "Work")
        var renamed = MemoryCategory.defaults[0]; renamed.name = "我的工作"
        XCTAssertEqual(renamed.displayName, "我的工作")
        let memory = Memory(title: "自己的标题", body: "原始内容")
        XCTAssertEqual(memory.displayTitle, "自己的标题")
        XCTAssertEqual(memory.body, "原始内容")
        XCTAssertEqual(memory.displaySource, "Manual note")
        L10n.language = .chinese
        XCTAssertEqual(MemoryCategory.defaults[0].displayName, "工作")
        XCTAssertEqual(memory.displaySource, "手动记录")
    }

    func testEnglishFormatStringsKeepTheSameArguments() throws {
        let placeholders = try NSRegularExpression(pattern: "%[@df]")
        func arguments(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }
        }
        for (key, translated) in Translations.english {
            XCTAssertFalse(translated.isEmpty, key)
            XCTAssertEqual(arguments(key), arguments(translated), key)
        }
    }

    func testLegacyPreferencesKeepForeverAndCustomShortcutsSurviveRoundTrip() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.retentionDays, 0)
        XCTAssertEqual(legacy.language, .system)
        XCTAssertTrue(legacy.moveToFrontAfterUse)
        XCTAssertTrue(Preferences().moveToFrontAfterUse)
        let previouslyDisabled = try JSONDecoder().decode(Preferences.self, from: Data(#"{"moveToFrontAfterPaste":false}"#.utf8))
        XCTAssertFalse(previouslyDisabled.moveToFrontAfterUse)
        XCTAssertEqual(Preferences().retentionDays, 30)
        XCTAssertEqual(HistoryRetention.presets.map(\.days), [1, 7, 30, 365, 0])
        var preferences = legacy
        preferences.moveToFrontAfterUse = false
        preferences.language = .english
        preferences.shortcuts[.activate] = .init(49, "Space", modifiers: KeyChord.command | KeyChord.option)
        preferences.shortcuts[.preview] = .disabled
        let reopened = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(reopened, preferences)
        XCTAssertFalse(reopened.shortcuts[.preview].enabled)
        XCTAssertEqual(reopened.shortcuts[.edit], ShortcutAction.edit.defaultChord)
    }

    func testShortcutConflictsAndUnsafeGlobalTypingAreRejected() throws {
        var preferences = ShortcutPreferences()
        try preferences.validate()
        XCTAssertEqual(preferences[.activate].display, "⇧⌘V")
        preferences[.search] = preferences[.edit]
        XCTAssertThrowsError(try preferences.validate())
        preferences[.edit] = .disabled
        XCTAssertNoThrow(try preferences.validate())
        preferences[.activate] = .init(0, "A", modifiers: KeyChord.shift)
        XCTAssertThrowsError(try preferences.validate())
        preferences = ShortcutPreferences()
        preferences[.quit] = .init(0, "A")
        XCTAssertThrowsError(try preferences.validate())
    }
}
