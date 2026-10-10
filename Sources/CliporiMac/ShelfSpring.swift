import Foundation

/// Exact damped spring integration keeps motion consistent across refresh rates and missed frames.
struct ShelfSpring {
    var value: Double
    var velocity: Double = 0

    mutating func advance(to target: Double, response: Double, damping: Double, by elapsed: Double) {
        guard elapsed > 0 else { return }
        let omega = 2 * Double.pi / response
        let displacement = value - target
        let decay = exp(-damping * omega * elapsed)
        if damping < 1 {
            let frequency = omega * sqrt(1 - damping * damping)
            let cosine = cos(frequency * elapsed), sine = sin(frequency * elapsed)
            value = target + decay * (displacement * cosine + (velocity + damping * omega * displacement) / frequency * sine)
            velocity = decay * (velocity * cosine - (damping * omega * velocity + omega * omega * displacement) / frequency * sine)
        } else {
            let coefficient = velocity + omega * displacement
            value = target + (displacement + coefficient * elapsed) * decay
            velocity = (velocity - omega * coefficient * elapsed) * decay
        }
    }

    func isSettled(at target: Double, distance: Double = 0.15, speed: Double = 2) -> Bool {
        abs(value - target) < distance && abs(velocity) < speed
    }
}
