import XCTest
@testable import CliporiMac

@MainActor
final class AccessibilityPermissionTests: XCTestCase {
    func testDecliningDoesNotPromptAgainAcrossLaunchesButAllowsExplicitRetry() async throws {
        let suite = "CliporiPermissionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var prompts = 0
        var settingsOpened = 0
        let permission = AccessibilityPermission(defaults: defaults, isTrusted: { false },
            prompt: { prompts += 1 }, openSettings: { settingsOpened += 1 })
        permission.request(automatically: true)
        permission.request(automatically: true)
        let relaunched = AccessibilityPermission(defaults: defaults, isTrusted: { false },
            prompt: { prompts += 1 }, openSettings: { settingsOpened += 1 })
        relaunched.request(automatically: true)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(settingsOpened, 0)
        relaunched.request(automatically: false)
        XCTAssertEqual(prompts, 2)
        XCTAssertEqual(settingsOpened, 1)
    }

    func testAuthorizedProcessDoesNotPromptOrOpenSettings() async throws {
        let suite = "CliporiPermissionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let permission = AccessibilityPermission(defaults: defaults, isTrusted: { true },
            prompt: { XCTFail("Already authorized") }, openSettings: { XCTFail("Already authorized") })
        permission.request(automatically: true)
        permission.request(automatically: false)
    }
}
