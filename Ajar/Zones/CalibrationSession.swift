import Foundation

/// Maximum-angle measurement: watch the angle for 3 s, keep the largest value.
/// Pure — the caller feeds samples and writes the result into `Calibration`.
struct CalibrationSession {
    static let duration: TimeInterval = 3.0
    /// Below this the lid clearly was not pushed to its stop; say so instead of storing junk.
    static let minimumValidMax = 90
    /// The lid must also travel upwards during the window. A fixed floor cannot tell a working
    /// position from a stop — on MacBookPro18,3 the working position is 115–120° and the stop is
    /// 131°, so any floor low enough to accept that stop also accepts sitting still. The rise
    /// can: pressing the button and not moving records nothing. Measured noise is ±1°.
    static let minimumRise = 5

    enum Outcome: Equatable {
        case measuring
        case succeeded(maxAngle: Int)
        case failed(observedMax: Int)
    }

    let startedAt: Date
    private(set) var observedMax = 0
    /// First angle seen, i.e. where the lid stood when the user pressed the button.
    private(set) var startAngle: Int?

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    mutating func observe(angle: Int, now: Date) -> Outcome {
        if startAngle == nil { startAngle = angle }
        observedMax = max(observedMax, angle)
        guard now.timeIntervalSince(startedAt) >= Self.duration else { return .measuring }
        let rise = observedMax - (startAngle ?? observedMax)
        return observedMax >= Self.minimumValidMax && rise >= Self.minimumRise
            ? .succeeded(maxAngle: observedMax)
            : .failed(observedMax: observedMax)
    }
}
