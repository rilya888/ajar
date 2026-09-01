import Foundation

/// Every zone knob in one place. The sensor is hardware: these are meant to be tuned,
/// not inlined. Defaults come from the measurements in docs/STATUS.md.
struct Calibration: Codable, Equatable {
    /// Measured on first launch by pushing the lid to its stop. `nil` = not calibrated,
    /// and then the `stop` zone does not exist. 131 on MacBookPro18,3.
    var maxAngle: Int?
    /// Closed lid reads exactly 0°, last non-zero value while closing is 4° — no values in between.
    var closedBelow = 3
    var lowThreshold = 45
    var hysteresis = 2
    var dwell: TimeInterval = 1.0
    /// `stop` = angle >= maxAngle - stopMargin.
    var stopMargin = 2
    /// A zone change only counts if the angle moved less than this during the dwell window.
    /// Measured: a full close crosses `low` in 1.28 s, so dwell alone would mute the mic
    /// every time the laptop is shut. A deliberate gesture ends with a lid that stopped moving.
    var stabilityDelta = 3

    // ponytail: no smoothing. Measured noise never exceeds ±1° and hysteresis covers it;
    // a moving average would only add lag. Add one if another model actually shows noise.

    /// Internal consistency for the Settings sliders: `closed` and `low` don't collide, and
    /// hysteresis can't push `low`'s held-open edge into `stop`'s. Settings rejects an edit that
    /// would make this false and rolls the field back — the rule lives here, not in the view.
    var isValid: Bool {
        guard lowThreshold > closedBelow else { return false }
        guard hysteresis >= 0 else { return false }
        guard dwell > 0 else { return false }
        if let maxAngle {
            guard lowThreshold + hysteresis < maxAngle - stopMargin else { return false }
        }
        return true
    }
}

extension Calibration {
    static let defaultsKey = "calibration"

    static func load(from defaults: UserDefaults = .standard) -> Calibration {
        guard let data = defaults.data(forKey: defaultsKey),
              let calibration = try? JSONDecoder().decode(Calibration.self, from: data) else {
            return Calibration()
        }
        return calibration
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
