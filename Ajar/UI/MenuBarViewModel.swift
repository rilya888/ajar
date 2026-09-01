import Foundation

/// Everything the menu bar shows, as plain values: `(angle, zone, suppression, tier) → strings`.
/// No SwiftUI here on purpose — this is the part worth testing.
struct MenuBarViewModel: Equatable {
    /// One row of "what happens where". `closed` has no row: nothing fires there and the
    /// screen is against the keyboard anyway.
    struct ZoneLine: Equatable, Identifiable {
        let zone: Zone
        let title: String
        let effect: String
        let isLocked: Bool
        let isCurrent: Bool
        var id: Zone { zone }
    }

    let hasSensor: Bool
    let angleText: String
    let zoneText: String
    let symbolName: String
    /// Suppressed but not paused: transient (startup, wake, closed lid) — dim, don't shout.
    let isDimmed: Bool
    /// Shown only while something is actually holding actions back.
    let statusLine: String?
    let zoneLines: [ZoneLine]
    let sensorMessage: String?
    /// A Shortcut failed (renamed, deleted, non-zero exit). Shown, not swallowed — otherwise
    /// the user just thinks the sensor broke.
    let shortcutErrorLine: String?

    static let compatibilityURL = URL(string: "https://quietunit.com/ajar/compatibility")!

    init(
        angle: Int?, zone: Zone, suppression: SuppressionState, tier: Tier,
        shortcutError: String? = nil, gesturesThisWeek: Int = 0, now: Date = Date()
    ) {
        shortcutErrorLine = shortcutError
        hasSensor = angle != nil
        angleText = angle.map { "\($0)°" } ?? "—"
        zoneText = hasSensor ? Self.name(of: zone) : "No sensor"
        sensorMessage = hasSensor ? nil : "This Mac has no lid angle sensor."

        let reason = suppression.reason(now: now)
        statusLine = hasSensor ? reason : nil

        if !hasSensor {
            symbolName = "laptopcomputer.trianglebadge.exclamationmark"
        } else if suppression.isPaused {
            symbolName = "laptopcomputer.slash"
        } else {
            symbolName = Self.symbol(for: zone)
        }
        isDimmed = hasSensor && !suppression.isPaused && reason != nil

        zoneLines = [
            ZoneLine(zone: .low, title: "Half-closed", effect: "Mutes the microphone",
                     isLocked: false, isCurrent: zone == .low),
            ZoneLine(zone: .normal, title: "Working position", effect: "Nothing happens",
                     isLocked: false, isCurrent: zone == .normal || zone == .closed),
            ZoneLine(zone: .stop, title: "Pushed to the stop", effect: "Turns on Do Not Disturb",
                     isLocked: false, isCurrent: zone == .stop)
        ]

        // ponytail: Stage 1 (free-first) — no tier line / upsell in the popover. `tier` and
        // `gesturesThisWeek` stay on the initializer for Block 13, which re-adds the line.
    }

    private static func name(of zone: Zone) -> String {
        switch zone {
        case .closed: return "Closed"
        case .low: return "Half-closed"
        case .normal: return "Working position"
        case .stop: return "At the stop"
        }
    }

    private static func symbol(for zone: Zone) -> String {
        switch zone {
        case .low: return "laptopcomputer.and.arrow.down"
        case .stop: return "laptopcomputer.badge.checkmark"
        case .closed, .normal: return "laptopcomputer"
        }
    }
}

extension SuppressionState {
    /// Why nothing will fire right now, in the same priority order `isSuppressed` uses.
    /// `nil` = actions are live.
    ///
    /// ponytail: no "external display connected" line — there is no clamshell code to report
    /// (see Suppressor). Add the string with the branch, not before it.
    func reason(now: Date) -> String? {
        if isPaused { return "Paused — actions are off" }
        if isAsleep { return "Asleep" }
        if now.timeIntervalSince(launchedAt) < SuppressionConfig.startupGrace { return "Starting up…" }
        if let wokeAt, now.timeIntervalSince(wokeAt) < SuppressionConfig.wakeGrace { return "Just woke up…" }
        if zone == .closed { return "Lid closed — nothing fires here" }
        return nil
    }
}
