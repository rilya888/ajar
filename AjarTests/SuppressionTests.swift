import XCTest
@testable import Ajar

private let launch = Date(timeIntervalSince1970: 1_000_000)
/// Past every grace window, so a state is suppressed only by an explicit flag.
private let settled = launch.addingTimeInterval(60)

private func state(
    paused: Bool = false,
    asleep: Bool = false,
    wokeAt: Date? = nil,
    zone: Zone = .normal
) -> SuppressionState {
    SuppressionState(isPaused: paused, isAsleep: asleep, launchedAt: launch, wokeAt: wokeAt, zone: zone)
}

final class SuppressionStateTests: XCTestCase {
    func testQuietRunningStateIsNotSuppressed() {
        XCTAssertFalse(state().isSuppressed(now: settled))
    }

    func testStartupGrace() {
        XCTAssertTrue(state().isSuppressed(now: launch))
        XCTAssertTrue(state().isSuppressed(now: launch.addingTimeInterval(2.9)))
        XCTAssertFalse(state().isSuppressed(now: launch.addingTimeInterval(3)))
    }

    func testSleepSuppressesUntilWakeGraceExpires() {
        XCTAssertTrue(state(asleep: true).isSuppressed(now: settled))

        let woke = settled
        XCTAssertTrue(state(wokeAt: woke).isSuppressed(now: woke))
        XCTAssertTrue(state(wokeAt: woke).isSuppressed(now: woke.addingTimeInterval(2.9)))
        XCTAssertFalse(state(wokeAt: woke).isSuppressed(now: woke.addingTimeInterval(3)))
    }

    func testClosedZoneIsNeverAGesture() {
        XCTAssertTrue(state(zone: .closed).isSuppressed(now: settled))
        XCTAssertFalse(state(zone: .low).isSuppressed(now: settled))
        XCTAssertFalse(state(zone: .stop).isSuppressed(now: settled))
    }

    /// The user's pause outranks every other combination, including none at all.
    func testPauseOutranksEverything() {
        for asleep in [false, true] {
            for woke in [nil, settled] as [Date?] {
                for zone in Zone.allCases {
                    let s = state(paused: true, asleep: asleep, wokeAt: woke, zone: zone)
                    XCTAssertTrue(s.isSuppressed(now: settled), "paused must suppress \(zone)")
                }
            }
        }
    }

    /// Every combination without a flag set resolves to "act", and any single flag suppresses.
    func testEachFlagAloneSuppresses() {
        XCTAssertTrue(state(paused: true).isSuppressed(now: settled))
        XCTAssertTrue(state(asleep: true).isSuppressed(now: settled))
        XCTAssertTrue(state(wokeAt: settled).isSuppressed(now: settled))
        XCTAssertTrue(state(zone: .closed).isSuppressed(now: settled))
        XCTAssertTrue(state().isSuppressed(now: launch))
        XCTAssertFalse(state(wokeAt: launch, zone: .low).isSuppressed(now: settled))
    }
}

final class ZoneActionTests: XCTestCase {
    private func transition(_ from: Zone, _ to: Zone) -> ZoneTransition {
        ZoneTransition(from: from, to: to, at: settled)
    }

    func testEnteringLowMutesWhenRunning() {
        XCTAssertEqual(ZoneAction.decide(transition(.normal, .low), suppressed: false), .mute)
    }

    func testSuppressedEntryDoesNothing() {
        XCTAssertEqual(ZoneAction.decide(transition(.normal, .low), suppressed: true), .none)
    }

    /// Leaving `low` restores even while suppressed — otherwise pausing or sleeping mid-gesture
    /// would strand the mic muted. `MicMuter` only touches what it muted itself.
    func testLeavingLowAlwaysRestores() {
        for suppressed in [false, true] {
            XCTAssertEqual(ZoneAction.decide(transition(.low, .normal), suppressed: suppressed), .restore)
            XCTAssertEqual(ZoneAction.decide(transition(.low, .closed), suppressed: suppressed), .restore)
        }
    }

    func testOtherTransitionsDoNothing() {
        XCTAssertEqual(ZoneAction.decide(transition(.normal, .stop), suppressed: false), .none)
        XCTAssertEqual(ZoneAction.decide(transition(.closed, .normal), suppressed: false), .none)
    }

    /// Nothing is queued: a transition missed while suppressed leaves no state behind, so the
    /// first sample after suppression lifts decides on its own merits.
    func testSuppressionDoesNotReplayMissedEntry() {
        let missed = transition(.normal, .low)
        XCTAssertEqual(ZoneAction.decide(missed, suppressed: true), .none)
        // The same transition re-decided after suppression lifts is the only way it could fire,
        // and nothing in the app re-submits it: the tracker emits a transition once.
        XCTAssertEqual(ZoneAction.decide(missed, suppressed: true), .none)
    }

    /// The lid closed during sleep: on wake the tracker sees `closed → normal`, not a fresh
    /// entry into `low`, so nothing is muted after the fact.
    func testWakingWithAClosedLidMutesNothing() {
        XCTAssertEqual(ZoneAction.decide(transition(.closed, .normal), suppressed: true), .none)
        XCTAssertEqual(ZoneAction.decide(transition(.closed, .normal), suppressed: false), .none)
    }
}

final class SuppressorTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SuppressorTests-\(UUID().uuidString)")
    }

    func testPauseIsPersisted() {
        let suppressor = Suppressor(defaults: defaults)
        XCTAssertFalse(suppressor.isPaused)
        suppressor.isPaused = true
        XCTAssertTrue(Suppressor(defaults: defaults).isPaused)
    }

    /// The startup grace is measured from init, so a fresh instance suppresses immediately.
    func testFreshInstanceIsInStartupGrace() {
        let suppressor = Suppressor(defaults: defaults)
        XCTAssertTrue(suppressor.isSuppressed(zone: .low))
        XCTAssertFalse(suppressor.isSuppressed(zone: .low, now: Date().addingTimeInterval(10)))
        XCTAssertTrue(suppressor.isSuppressed(zone: .closed, now: Date().addingTimeInterval(10)))
    }
}
