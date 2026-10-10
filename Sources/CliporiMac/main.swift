import AppKit

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let applicationDelegate = ApplicationDelegate()
    application.delegate = applicationDelegate
    withExtendedLifetime(applicationDelegate) { application.run() }
}
