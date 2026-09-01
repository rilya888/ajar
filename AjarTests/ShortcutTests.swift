import XCTest
@testable import Ajar

private let settled = Date(timeIntervalSince1970: 3_000_000)

private func transition(_ from: Zone, _ to: Zone) -> ZoneTransition {
    ZoneTransition(from: from, to: to, at: settled)
}

final class ShortcutBindingsTests: XCTestCase {
    func testUnboundEdgeReturnsNil() {
        let bindings = ShortcutBindings()
        XCTAssertNil(bindings.shortcut(for: .stop, edge: .enter))
    }

    func testSetAndGetRoundTrip() {
        var bindings = ShortcutBindings()
        bindings.set("Turn on Focus", for: .stop, edge: .enter)
        bindings.set("Turn off Focus", for: .stop, edge: .exit)
        XCTAssertEqual(bindings.shortcut(for: .stop, edge: .enter), "Turn on Focus")
        XCTAssertEqual(bindings.shortcut(for: .stop, edge: .exit), "Turn off Focus")
        // Different zone/edge combinations don't leak into each other.
        XCTAssertNil(bindings.shortcut(for: .low, edge: .enter))
        XCTAssertNil(bindings.shortcut(for: .low, edge: .exit))
    }

    func testNilClearsABinding() {
        var bindings = ShortcutBindings()
        bindings.set("Turn on Focus", for: .stop, edge: .enter)
        bindings.set(nil, for: .stop, edge: .enter)
        XCTAssertNil(bindings.shortcut(for: .stop, edge: .enter))
    }

    func testEmptyStringClearsABindingTooSoTheUIsNoneOptionWorks() {
        var bindings = ShortcutBindings()
        bindings.set("Turn on Focus", for: .stop, edge: .enter)
        bindings.set("", for: .stop, edge: .enter)
        XCTAssertNil(bindings.shortcut(for: .stop, edge: .enter))
    }

    func testPersistsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "ShortcutBindingsTests-\(UUID().uuidString)")!
        var bindings = ShortcutBindings()
        bindings.set("Turn on Focus", for: .stop, edge: .enter)
        bindings.set("Mute Music", for: .low, edge: .enter)
        bindings.save(to: defaults)

        let reloaded = ShortcutBindings.load(from: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .stop, edge: .enter), "Turn on Focus")
        XCTAssertEqual(reloaded.shortcut(for: .low, edge: .enter), "Mute Music")
    }

    func testLoadWithNothingSavedReturnsEmptyBindings() {
        let defaults = UserDefaults(suiteName: "ShortcutBindingsTests-\(UUID().uuidString)")!
        let bindings = ShortcutBindings.load(from: defaults)
        XCTAssertNil(bindings.shortcut(for: .low, edge: .enter))
    }
}

final class ShortcutActionTests: XCTestCase {
    func testFreeTierAlwaysRunsTheDefaultShortcuts() {
        let bindings = ShortcutBindings()
        XCTAssertEqual(
            ShortcutAction.decide(transition(.normal, .stop), bindings: bindings, tier: .free, suppressed: false),
            [DefaultShortcuts.stopEnter]
        )
        XCTAssertEqual(
            ShortcutAction.decide(transition(.stop, .normal), bindings: bindings, tier: .free, suppressed: false),
            [DefaultShortcuts.stopExit]
        )
    }

    func testTrialOrProUsesTheCustomBindingInsteadOfTheDefault() {
        var bindings = ShortcutBindings()
        bindings.set("My Focus On", for: .stop, edge: .enter)
        bindings.set("My Focus Off", for: .stop, edge: .exit)

        XCTAssertEqual(
            ShortcutAction.decide(transition(.normal, .stop), bindings: bindings, tier: .pro, suppressed: false),
            ["My Focus On"]
        )
        XCTAssertEqual(
            ShortcutAction.decide(transition(.stop, .normal), bindings: bindings, tier: .trial(daysLeft: 3), suppressed: false),
            ["My Focus Off"]
        )
    }

    /// The core of the "revert on trial expiry" product decision: a custom pick made during
    /// trial/Pro survives in `ShortcutBindings`, it just stops being read once the tier can't
    /// unlock Pro — buying a license later brings it straight back, nothing was deleted.
    func testFreeTierIgnoresAStaleCustomBindingFromAnExpiredTrial() {
        var bindings = ShortcutBindings()
        bindings.set("My Focus On", for: .stop, edge: .enter)
        let names = ShortcutAction.decide(transition(.normal, .stop), bindings: bindings, tier: .free, suppressed: false)
        XCTAssertEqual(names, [DefaultShortcuts.stopEnter])
    }

    func testLowZoneNeverRunsAShortcutEvenIfSomehowBound() {
        var bindings = ShortcutBindings()
        bindings.set("Should never run", for: .low, edge: .enter)
        bindings.set("Should never run either", for: .low, edge: .exit)

        XCTAssertTrue(
            ShortcutAction.decide(transition(.normal, .low), bindings: bindings, tier: .pro, suppressed: false).isEmpty
        )
        XCTAssertTrue(
            ShortcutAction.decide(transition(.low, .normal), bindings: bindings, tier: .pro, suppressed: false).isEmpty
        )
    }

    /// Suppression must never strand whatever the enter shortcut turned on — same reasoning as
    /// `MicMuter`'s honest restore. Only entry is gated.
    func testSuppressionHidesEnterButNeverExit() {
        XCTAssertTrue(
            ShortcutAction.decide(transition(.normal, .stop), bindings: ShortcutBindings(), tier: .pro, suppressed: true).isEmpty
        )
        XCTAssertEqual(
            ShortcutAction.decide(transition(.stop, .normal), bindings: ShortcutBindings(), tier: .pro, suppressed: true),
            [DefaultShortcuts.stopExit]
        )
    }
}

final class ShortcutRunGateTests: XCTestCase {
    func testFirstStartSucceeds() {
        var gate = ShortcutRunGate()
        XCTAssertTrue(gate.start("Turn on Focus"))
    }

    /// The core requirement from the block: a fast series of gestures must not queue up
    /// repeated launches of the same Shortcut.
    func testConcurrentStartOfTheSameNameIsRefused() {
        var gate = ShortcutRunGate()
        XCTAssertTrue(gate.start("Turn on Focus"))
        XCTAssertFalse(gate.start("Turn on Focus"))
    }

    func testDifferentNamesRunIndependently() {
        var gate = ShortcutRunGate()
        XCTAssertTrue(gate.start("Turn on Focus"))
        XCTAssertTrue(gate.start("Mute Music"))
    }

    func testNameCanRunAgainAfterItFinishes() {
        var gate = ShortcutRunGate()
        XCTAssertTrue(gate.start("Turn on Focus"))
        gate.finished("Turn on Focus")
        XCTAssertTrue(gate.start("Turn on Focus"))
    }

    func testFinishingAnUnstartedNameIsHarmless() {
        var gate = ShortcutRunGate()
        gate.finished("Never started")
        XCTAssertTrue(gate.start("Never started"))
    }
}
