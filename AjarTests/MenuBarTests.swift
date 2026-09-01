import XCTest
@testable import Ajar

private let launch = Date(timeIntervalSince1970: 2_000_000)
/// Past every grace window: only explicit flags suppress here.
private let settled = launch.addingTimeInterval(60)

private func suppression(
    paused: Bool = false,
    asleep: Bool = false,
    wokeAt: Date? = nil,
    zone: Zone = .normal
) -> SuppressionState {
    SuppressionState(isPaused: paused, isAsleep: asleep, launchedAt: launch, wokeAt: wokeAt, zone: zone)
}

private func model(
    angle: Int? = 115,
    zone: Zone = .normal,
    suppression state: SuppressionState? = nil,
    tier: Tier = .pro,
    now: Date = settled
) -> MenuBarViewModel {
    MenuBarViewModel(
        angle: angle,
        zone: zone,
        suppression: state ?? suppression(zone: zone),
        tier: tier,
        now: now
    )
}

final class MenuBarViewModelTests: XCTestCase {
    func testLiveAngleAndZoneWording() {
        let live = model(angle: 115, zone: .normal)
        XCTAssertEqual(live.angleText, "115°")
        XCTAssertEqual(live.zoneText, "Working position")
        XCTAssertEqual(live.symbolName, "laptopcomputer")
        XCTAssertNil(live.statusLine)
        XCTAssertFalse(live.isDimmed)
    }

    func testEveryZoneHasItsOwnWordAndSymbol() {
        let words = Zone.allCases.map { model(zone: $0).zoneText }
        XCTAssertEqual(words, ["Closed", "Half-closed", "Working position", "At the stop"])
        XCTAssertEqual(model(zone: .low).symbolName, "laptopcomputer.and.arrow.down")
        XCTAssertEqual(model(zone: .stop).symbolName, "laptopcomputer.badge.checkmark")
        XCTAssertEqual(model(zone: .closed).symbolName, "laptopcomputer")
    }

    func testCurrentZoneIsMarkedAndClosedFallsBackToTheIdleRow() {
        XCTAssertEqual(model(zone: .low).zoneLines.filter(\.isCurrent).map(\.zone), [.low])
        XCTAssertEqual(model(zone: .stop).zoneLines.filter(\.isCurrent).map(\.zone), [.stop])
        // No row of its own: closed fires nothing, and the screen is shut anyway.
        XCTAssertEqual(model(zone: .closed).zoneLines.filter(\.isCurrent).map(\.zone), [.normal])
    }

    // MARK: sensor missing

    func testNoSensorIsSaidOutLoud() {
        let none = model(angle: nil)
        XCTAssertFalse(none.hasSensor)
        XCTAssertEqual(none.angleText, "—")
        XCTAssertEqual(none.zoneText, "No sensor")
        XCTAssertEqual(none.sensorMessage, "This Mac has no lid angle sensor.")
        XCTAssertEqual(none.symbolName, "laptopcomputer.trianglebadge.exclamationmark")
    }

    func testNoSensorHidesSuppressionNoise() {
        let none = model(angle: nil, suppression: suppression(zone: .closed))
        XCTAssertNil(none.statusLine)
        XCTAssertFalse(none.isDimmed)
    }

    // MARK: suppression

    func testPauseGetsItsOwnSymbolInsteadOfDimming() {
        let paused = model(suppression: suppression(paused: true))
        XCTAssertEqual(paused.symbolName, "laptopcomputer.slash")
        XCTAssertEqual(paused.statusLine, "Paused — actions are off")
        XCTAssertFalse(paused.isDimmed)
    }

    func testTransientSuppressionDimsAndExplains() {
        let starting = model(now: launch.addingTimeInterval(1))
        XCTAssertTrue(starting.isDimmed)
        XCTAssertEqual(starting.statusLine, "Starting up…")

        let woke = model(suppression: suppression(wokeAt: settled), now: settled.addingTimeInterval(1))
        XCTAssertTrue(woke.isDimmed)
        XCTAssertEqual(woke.statusLine, "Just woke up…")

        let closed = model(zone: .closed)
        XCTAssertTrue(closed.isDimmed)
        XCTAssertEqual(closed.statusLine, "Lid closed — nothing fires here")
    }

    func testReasonFollowsTheSuppressionPriority() {
        // Same order as isSuppressed: pause outranks sleep outranks graces outranks closed.
        let everything = suppression(paused: true, asleep: true, wokeAt: launch, zone: .closed)
        XCTAssertEqual(everything.reason(now: launch), "Paused — actions are off")
        XCTAssertEqual(suppression(asleep: true, zone: .closed).reason(now: settled), "Asleep")
        XCTAssertNil(suppression().reason(now: settled))
    }

    func testReasonExistsExactlyWhenActionsAreSuppressed() {
        let cases = [
            suppression(),
            suppression(paused: true),
            suppression(asleep: true),
            suppression(wokeAt: settled),
            suppression(zone: .closed)
        ]
        for state in cases {
            let now = settled.addingTimeInterval(1)
            XCTAssertEqual(state.reason(now: now) != nil, state.isSuppressed(now: now))
        }
    }

    // MARK: tiers

    /// The `stop` row itself is never locked — Free always runs the default Do Not Disturb
    /// shortcut. Only *swapping* it for something else is Pro-gated, in Settings ▸ Zones.
    func testStopZoneIsNeverLockedInThePopover() {
        for tier in [Tier.free, .pro, .trial(daysLeft: 1)] {
            let stop = model(tier: tier).zoneLines.first { $0.zone == .stop }!
            XCTAssertFalse(stop.isLocked)
            XCTAssertEqual(stop.effect, "Turns on Do Not Disturb")
        }
    }

    func testMuteRowIsNeverGated() {
        for tier in [Tier.free, .pro, .trial(daysLeft: 14)] {
            let low = model(tier: tier).zoneLines.first { $0.zone == .low }!
            XCTAssertFalse(low.isLocked)
            XCTAssertEqual(low.effect, "Mutes the microphone")
        }
    }

    // Stage 1 (free-first): no tier line / upsell in the popover at all. The old
    // testTierLineNeverCountsDown / UpsellLineTests went with it. Block 13 re-adds them.
}
