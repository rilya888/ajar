import Foundation

struct ZoneTransition: Equatable {
    let from: Zone
    let to: Zone
    let at: Date
}

/// Dwell layer above `ZoneEngine`: a zone change is committed only after it held for `dwell`
/// with the lid standing still. Time comes in as a parameter — nothing calls `Date()` in here.
struct ZoneTracker {
    var calibration: Calibration
    private(set) var zone: Zone

    /// The pending zone: when it started holding, and the angle that window is measured from.
    private var candidate: (zone: Zone, since: Date, anchor: Int)?

    init(calibration: Calibration, zone: Zone = .normal) {
        self.calibration = calibration
        self.zone = zone
    }

    /// Feed one sample. Returns a transition only on the sample that commits it.
    mutating func update(angle: Int, now: Date) -> ZoneTransition? {
        let raw = ZoneEngine.zone(angle: angle, previous: zone, calibration: calibration)

        guard raw != zone else {
            candidate = nil
            return nil
        }

        guard var pending = candidate, pending.zone == raw else {
            candidate = (zone: raw, since: now, anchor: angle)
            return nil
        }

        // Still moving: the window restarts, so a lid passing through a zone never commits.
        if abs(angle - pending.anchor) >= calibration.stabilityDelta {
            pending.anchor = angle
            pending.since = now
        }
        candidate = pending

        guard now.timeIntervalSince(pending.since) >= calibration.dwell else { return nil }

        let transition = ZoneTransition(from: zone, to: raw, at: now)
        zone = raw
        candidate = nil
        return transition
    }
}
