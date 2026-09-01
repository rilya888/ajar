import AppKit
import Foundation
import Observation

/// Every "do nothing right now" knob in one place.
enum SuppressionConfig {
    /// Auto-launch at login with a half-closed lid must not fire on the first samples.
    static let startupGrace: TimeInterval = 3
    /// Not the sensor's fault — it reads correctly on the first sample after waking.
    /// The lid crosses `low` by definition while being opened.
    static let wakeGrace: TimeInterval = 3
}

/// Pure snapshot of every reason to stay quiet. Time comes in as a parameter.
struct SuppressionState: Equatable {
    var isPaused = false
    var isAsleep = false
    var launchedAt: Date
    var wokeAt: Date?
    var zone: Zone = .normal

    func isSuppressed(now: Date) -> Bool {
        if isPaused { return true }                 // user's pause outranks everything
        if isAsleep { return true }
        if now.timeIntervalSince(launchedAt) < SuppressionConfig.startupGrace { return true }
        if let wokeAt, now.timeIntervalSince(wokeAt) < SuppressionConfig.wakeGrace { return true }
        return zone == .closed                      // shutting the laptop is not a gesture
    }
}

/// What a committed transition should do. Leaving a zone always restores: suppression must
/// never strand the mic muted, and `MicMuter` only touches what it muted itself.
enum ZoneAction: Equatable {
    case mute
    case restore
    case none

    /// No queue anywhere: a decision exists only for the transition being handled, so
    /// leaving suppression never replays what was missed.
    static func decide(_ transition: ZoneTransition, suppressed: Bool) -> ZoneAction {
        switch (transition.from, transition.to) {
        case (.low, _): return .restore
        case (_, .low): return suppressed ? .none : .mute
        default: return .none
        }
    }
}

/// Thin flag collector around the pure state: sleep/wake notifications, the launch clock
/// and the user's pause switch.
///
/// ponytail: no clamshell branch, and the measurement on a real external monitor says none is
/// needed. Lid shut with the machine awake in clamshell: no action at all — `closed` is inert
/// and a normal close crosses `low` in 0.4 s, far too fast to hold. A *slow* close does mute,
/// for 2.7 s, and then restores itself on `low → closed`; that is the gesture performed
/// correctly, and it happens identically with no monitor attached — there the machine is
/// asleep by then and nobody hears it. `CGDisplayIsBuiltin` would not change any of this,
/// so it stays out. Numbers: docs/research/clamshell-2026-08-12.log.
@Observable
final class Suppressor {
    static let pausedKey = "isPaused"

    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Self.pausedKey) }
    }

    /// UI only: a grace ends by the clock, not by an event, so nothing would tell the menu bar
    /// to redraw. Bumped when a grace expires; the pure state still decides from the dates.
    private(set) var graceRevision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let launchedAt = Date()
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var wokeAt: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: Self.pausedKey)

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = true
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = false
                self?.wokeAt = Date()
                self?.nudgeAfter(SuppressionConfig.wakeGrace)
            }
        ]
        nudgeAfter(SuppressionConfig.startupGrace)
    }

    private func nudgeAfter(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.graceRevision += 1
        }
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func state(zone: Zone) -> SuppressionState {
        SuppressionState(
            isPaused: isPaused,
            isAsleep: isAsleep,
            launchedAt: launchedAt,
            wokeAt: wokeAt,
            zone: zone
        )
    }

    func isSuppressed(zone: Zone, now: Date = Date()) -> Bool {
        state(zone: zone).isSuppressed(now: now)
    }
}
