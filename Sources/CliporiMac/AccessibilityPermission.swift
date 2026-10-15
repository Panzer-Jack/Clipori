import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermission {
    private let defaults: UserDefaults
    private let isTrusted: () -> Bool
    private let prompt: () -> Void
    private let openSettings: () -> Void
    private let requestedKey = "accessibilityPermissionRequested"

    init(defaults: UserDefaults = .standard,
         isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         prompt: @escaping () -> Void = {
             let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
             AXIsProcessTrustedWithOptions(options as CFDictionary)
         },
         openSettings: @escaping () -> Void = {
             if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                 NSWorkspace.shared.open(url)
             }
         }) {
        self.defaults = defaults; self.isTrusted = isTrusted
        self.prompt = prompt; self.openSettings = openSettings
    }

    func request(automatically: Bool) {
        guard !isTrusted() else { return }
        // Remember a declined prompt across launches; only an explicit retry asks again.
        guard !automatically || !defaults.bool(forKey: requestedKey) else { return }
        defaults.set(true, forKey: requestedKey)
        prompt()
        // macOS can suppress repeated prompts. The settings button must still lead somewhere.
        if !automatically { openSettings() }
    }
}
