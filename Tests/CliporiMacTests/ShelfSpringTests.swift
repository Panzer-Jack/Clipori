import XCTest
@testable import CliporiMac

final class ShelfSpringTests: XCTestCase {
    func testOpeningHasSmallOvershootAndSettlesQuickly() {
        var spring = ShelfSpring(value: -64)
        var peak = -64.0
        for _ in 0..<60 {
            spring.advance(to: 0, response: 0.30, damping: 0.58, by: 1.0 / 120)
            peak = max(peak, spring.value)
        }
        XCTAssertGreaterThan(peak, 5)
        XCTAssertLessThan(peak, 9, "Keep the stronger rebound controlled")
        XCTAssertLessThan(abs(spring.value), 0.2)
        spring.advance(to: 0, response: 0.30, damping: 0.58, by: 0.1)
        XCTAssertTrue(spring.isSettled(at: 0))
    }

    func testRefreshRatesAndMissedFramesProduceTheSamePosition() {
        func sample(steps: [Double]) -> ShelfSpring {
            var spring = ShelfSpring(value: -64)
            for step in steps { spring.advance(to: 0, response: 0.30, damping: 0.58, by: step) }
            return spring
        }
        let sixty = sample(steps: Array(repeating: 1.0 / 60, count: 12))
        let highRefresh = sample(steps: Array(repeating: 1.0 / 120, count: 24))
        let missedFrame = sample(steps: [0.016, 0.016, 0.1, 0.068])
        XCTAssertEqual(sixty.value, highRefresh.value, accuracy: 0.0001)
        XCTAssertEqual(sixty.velocity, highRefresh.velocity, accuracy: 0.0001)
        XCTAssertEqual(sixty.value, missedFrame.value, accuracy: 0.0001)
        XCTAssertEqual(sixty.velocity, missedFrame.velocity, accuracy: 0.0001)
    }

    func testRapidReversalKeepsContinuityAndClosingDoesNotOvershoot() {
        var spring = ShelfSpring(value: -64)
        spring.advance(to: 0, response: 0.30, damping: 0.58, by: 0.08)
        let before = spring.value
        spring.advance(to: -24, response: 0.22, damping: 1, by: 0.0001)
        XCTAssertLessThan(abs(spring.value - before), 0.1)
        for _ in 0..<120 { spring.advance(to: -24, response: 0.22, damping: 1, by: 1.0 / 120) }
        XCTAssertTrue(spring.isSettled(at: -24))
        var opacity = ShelfSpring(value: 1)
        for _ in 0..<60 {
            opacity.advance(to: 0, response: 0.14, damping: 1, by: 1.0 / 120)
            XCTAssertGreaterThanOrEqual(opacity.value, 0)
            XCTAssertLessThanOrEqual(opacity.value, 1)
        }
    }
}
