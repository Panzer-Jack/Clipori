import AppKit
import Darwin
import XCTest
import CliporiCore
@testable import CliporiMac

/// Opt-in release benchmark. Uses synthetic history and a private pasteboard only.
/// CLIPORI_PERFORMANCE_OUTPUT=/absolute/report.json swift test -c release --filter PerformanceTests
@MainActor
final class PerformanceTests: XCTestCase {
    func testLocalPerformance() async throws {
        guard let output = ProcessInfo.processInfo.environment["CLIPORI_PERFORMANCE_OUTPUT"] else {
            throw XCTSkip("Set CLIPORI_PERFORMANCE_OUTPUT to run the interactive release benchmark")
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try AppModel(directory: directory, preview: false)
        var preferences = Preferences(); preferences.retentionDays = 0
        try await model.store.savePreferences(preferences)
        let payload = String(repeating: "Synthetic clipboard note: code, design, weekend plans. ", count: 20)
        for index in 0..<10_000 {
            let marker = index == 321 ? "青山食堂 花园路18号 周末聚餐 " : ""
            try await model.store.save(Memory(body: "\(index) \(marker)\(payload)"))
        }
        await model.start()
        XCTAssertTrue(model.ready)
        var report: [String: Any] = ["history_count": 10_000, "record_bytes_approx": payload.utf8.count,
                                   "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                   "logical_cpus": ProcessInfo.processInfo.processorCount]
        var page: [Double] = [], keyword: [Double] = [], candidates: [Double] = []
        for _ in 0..<50 {
            page.append(try await milliseconds { _ = try await model.store.list(limit: 80) })
            keyword.append(try await milliseconds { _ = try await model.store.list(query: "青山") })
            candidates.append(try await milliseconds { _ = try await model.store.candidates(plan: SearchPlan(keywords: ["食堂", "聚餐"])) })
        }
        report["page_80"] = summary(page)
        report["keyword"] = summary(keyword)
        report["ai_local_candidates"] = summary(candidates)
        report["database_bytes"] = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]).reduce(0) {
            $0 + ((try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(model: model, pasteboard: board, source: { .init(name: "Performance fixture", bundleID: "test.performance", processID: nil) })
        monitor.start(observeExternalEvents: false)
        defer { monitor.stop() }
        let idleCPU = cpuSeconds(), idleStart = CACurrentMediaTime()
        try await Task.sleep(for: .seconds(12))
        report["hidden_idle_cpu_percent_one_core"] = 100 * (cpuSeconds() - idleCPU) / (CACurrentMediaTime() - idleStart)

        var captures: [Double] = []
        let captureCPU = cpuSeconds(), captureStart = CACurrentMediaTime()
        for index in 0..<20 {
            try await Task.sleep(for: .milliseconds((index * 73) % 450))
            let expected = model.captureCount + 1
            let start = CACurrentMediaTime()
            board.clearContents(); board.setString("Capture \(index): \(payload)", forType: .string)
            while model.captureCount < expected && CACurrentMediaTime() - start < 2 {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertEqual(model.captureCount, expected)
            captures.append((CACurrentMediaTime() - start) * 1000)
        }
        report["copy_to_saved_with_polling"] = summary(captures)
        report["copy_20_cpu_seconds"] = cpuSeconds() - captureCPU
        report["copy_20_elapsed_seconds"] = CACurrentMediaTime() - captureStart

        let controller = ShelfController(model: model)
        defer { controller.hide(restoreFocus: false) }
        var showCalls: [Double] = [], firstVisible: [Double] = [], nearTarget: [Double] = [], motionStop: [Double] = []
        var cycleResults: [[String: Double]] = []
        let animationCPU = cpuSeconds(), animationStart = CACurrentMediaTime()
        for _ in 0..<10 {
            let start = CACurrentMediaTime()
            controller.show()
            showCalls.append((CACurrentMediaTime() - start) * 1000)
            var frames: [(time: Double, y: Double, alpha: Double)] = []
            while CACurrentMediaTime() - start < 0.7 {
                frames.append(((CACurrentMediaTime() - start) * 1000, controller.panel.frame.minY, controller.panel.alphaValue))
                try await Task.sleep(for: .milliseconds(8))
            }
            let finalY = controller.panel.frame.minY
            if let frame = frames.first(where: { $0.alpha >= 0.1 }) { firstVisible.append(frame.time) }
            if let frame = frames.first(where: { abs($0.y - finalY) <= 3 && $0.alpha >= 0.95 }) { nearTarget.append(frame.time) }
            if let lastMoving = frames.last(where: { abs($0.y - finalY) > 0.2 || $0.alpha < 0.99 }) { motionStop.append(lastMoving.time) }
            cycleResults.append(["cycle": Double(cycleResults.count + 1), "first_visible_ms": firstVisible.last ?? -1,
                                 "near_target_ms": nearTarget.last ?? -1, "last_unsettled_ms": motionStop.last ?? -1])
            controller.hide(restoreFocus: false)
            try await Task.sleep(for: .milliseconds(650))
        }
        report["show_call"] = summary(showCalls)
        report["show_first_visible_sampled"] = summary(firstVisible)
        report["show_near_target_sampled"] = summary(nearTarget)
        report["show_last_unsettled_sampled"] = summary(motionStop)
        report["show_cycles"] = cycleResults
        report["show_hide_10_cycles_cpu_seconds"] = cpuSeconds() - animationCPU
        report["show_hide_10_cycles_elapsed_seconds"] = CACurrentMediaTime() - animationStart
        report["test_host_peak_rss_mb"] = peakMemoryMB()
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        print("Performance report: \(output)")
    }

    private func milliseconds(_ operation: () async throws -> Void) async rethrows -> Double {
        let start = CACurrentMediaTime()
        try await operation()
        return (CACurrentMediaTime() - start) * 1000
    }
    private func summary(_ values: [Double]) -> [String: Double] {
        guard !values.isEmpty else { return [:] }
        let sorted = values.sorted()
        return ["count": Double(values.count), "p50_ms": sorted[(sorted.count - 1) / 2],
                "p95_ms": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1], "max_ms": sorted.last!]
    }
    private func cpuSeconds() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    private func peakMemoryMB() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
    }
}
