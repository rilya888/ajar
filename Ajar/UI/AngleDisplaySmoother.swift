import Foundation

/// Smooths the ±1° sensor jitter measured at quantization boundaries (docs/STATUS.md, item 18:
/// 39 flips between 119° and 120° in 19 s) so the live indicator in Settings doesn't blink.
/// A reading is only adopted once it has held steady for `holdTime`; the sensor going away is
/// shown immediately since that isn't jitter.
struct AngleDisplaySmoother {
    static let holdTime: TimeInterval = 0.3

    private(set) var displayed: Int?
    private var pending: (angle: Int, since: Date)?

    init(displayed: Int? = nil) {
        self.displayed = displayed
    }

    mutating func update(angle: Int?, now: Date) -> Int? {
        guard let angle else {
            displayed = nil
            pending = nil
            return displayed
        }
        if pending?.angle != angle {
            pending = (angle, now)
        }
        if let pending, now.timeIntervalSince(pending.since) >= Self.holdTime {
            displayed = pending.angle
        }
        return displayed
    }
}
