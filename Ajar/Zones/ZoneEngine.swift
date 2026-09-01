/// Angle → zone. Pure, so the heart of the product needs no hardware to test.
enum ZoneEngine {
    /// Hysteresis widens only the zone you are already in: sitting in `low` the zone holds
    /// until `lowThreshold + hysteresis`, coming from `normal` it flips at `lowThreshold`.
    /// The `closed` boundary is exact — measurement shows a 4° gap around it, nothing to debounce.
    static func zone(angle: Int, previous: Zone, calibration c: Calibration) -> Zone {
        if angle <= c.closedBelow { return .closed }

        if let maxAngle = c.maxAngle {
            let threshold = previous == .stop
                ? maxAngle - c.stopMargin - c.hysteresis
                : maxAngle - c.stopMargin
            if angle >= threshold { return .stop }
        }

        let threshold = previous == .low ? c.lowThreshold + c.hysteresis : c.lowThreshold
        return angle < threshold ? .low : .normal
    }
}
