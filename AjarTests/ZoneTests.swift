import XCTest
@testable import Ajar

/// Calibrated like the dev machine: max 131°, so `stop` starts at 129°.
private let measured = Calibration(maxAngle: 131)

final class ZoneEngineTests: XCTestCase {
    private func zone(_ angle: Int, from previous: Zone, _ c: Calibration = measured) -> Zone {
        ZoneEngine.zone(angle: angle, previous: previous, calibration: c)
    }

    func testAllZonesFromWorkingPosition() {
        XCTAssertEqual(zone(0, from: .normal), .closed)
        XCTAssertEqual(zone(3, from: .normal), .closed)
        XCTAssertEqual(zone(4, from: .normal), .low)
        XCTAssertEqual(zone(44, from: .normal), .low)
        XCTAssertEqual(zone(45, from: .normal), .normal)
        XCTAssertEqual(zone(115, from: .normal), .normal)
        XCTAssertEqual(zone(128, from: .normal), .normal)
        XCTAssertEqual(zone(129, from: .normal), .stop)
        XCTAssertEqual(zone(131, from: .normal), .stop)
    }

    func testTransitionsOutOfEveryZone() {
        XCTAssertEqual(zone(115, from: .closed), .normal)
        XCTAssertEqual(zone(129, from: .low), .stop)
        XCTAssertEqual(zone(0, from: .stop), .closed)
        XCTAssertEqual(zone(0, from: .low), .closed)
        XCTAssertEqual(zone(20, from: .stop), .low)
    }

    func testHysteresisHoldsLowUntilThresholdPlusMargin() {
        XCTAssertEqual(zone(45, from: .low), .low)
        XCTAssertEqual(zone(46, from: .low), .low)
        XCTAssertEqual(zone(47, from: .low), .normal)
        // Coming from above, the border is the bare threshold.
        XCTAssertEqual(zone(46, from: .normal), .normal)
        XCTAssertEqual(zone(44, from: .normal), .low)
    }

    func testHysteresisHoldsStopUntilThresholdMinusMargin() {
        XCTAssertEqual(zone(128, from: .stop), .stop)
        XCTAssertEqual(zone(127, from: .stop), .stop)
        XCTAssertEqual(zone(126, from: .stop), .normal)
        XCTAssertEqual(zone(128, from: .normal), .normal)
    }

    func testClosedBoundaryHasNoHysteresis() {
        XCTAssertEqual(zone(3, from: .low), .closed)
        XCTAssertEqual(zone(4, from: .closed), .low)
    }

    func testStopIsUnreachableWithoutCalibration() {
        let uncalibrated = Calibration()
        for angle in 0...180 {
            XCTAssertNotEqual(zone(angle, from: .normal, uncalibrated), .stop)
            XCTAssertNotEqual(zone(angle, from: .stop, uncalibrated), .stop)
        }
    }

    func testDegenerateCalibrationsStillTerminate() {
        // lowThreshold above maxAngle, and closedBelow above lowThreshold: nonsense settings,
        // but every angle must still map to exactly one zone and stay there.
        let cases = [
            Calibration(maxAngle: 40, lowThreshold: 45),
            Calibration(maxAngle: 131, closedBelow: 60, lowThreshold: 45),
            Calibration(maxAngle: 0, closedBelow: 0, lowThreshold: 0, hysteresis: 50),
        ]
        for c in cases {
            for angle in 0...180 {
                for previous in Zone.allCases {
                    let first = zone(angle, from: previous, c)
                    XCTAssertEqual(zone(angle, from: first, c), first, "oscillates at \(angle) in \(c)")
                }
            }
        }
    }
}

final class ZoneTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testZoneHeldLongEnoughCommits() {
        var tracker = ZoneTracker(calibration: measured)
        XCTAssertNil(tracker.update(angle: 30, now: t0))
        XCTAssertNil(tracker.update(angle: 30, now: t0 + 0.5))
        let transition = tracker.update(angle: 30, now: t0 + 1.0)
        XCTAssertEqual(transition, ZoneTransition(from: .normal, to: .low, at: t0 + 1.0))
        XCTAssertEqual(tracker.zone, .low)
    }

    func testZoneNotHeldLongEnoughDoesNotCommit() {
        var tracker = ZoneTracker(calibration: measured)
        XCTAssertNil(tracker.update(angle: 30, now: t0))
        XCTAssertNil(tracker.update(angle: 30, now: t0 + 0.9))
        XCTAssertNil(tracker.update(angle: 115, now: t0 + 1.0))
        XCTAssertNil(tracker.update(angle: 115, now: t0 + 5.0))
        XCTAssertEqual(tracker.zone, .normal)
    }

    func testZoneChangingTwiceInsideWindowRestartsTheClock() {
        var tracker = ZoneTracker(calibration: measured)
        XCTAssertNil(tracker.update(angle: 30, now: t0))
        XCTAssertNil(tracker.update(angle: 130, now: t0 + 0.4))   // candidate becomes stop
        XCTAssertNil(tracker.update(angle: 130, now: t0 + 1.1))   // 0.7 s of stop is not enough
        XCTAssertEqual(tracker.update(angle: 130, now: t0 + 1.4),
                       ZoneTransition(from: .normal, to: .stop, at: t0 + 1.4))
    }

    func testMovingLidRestartsTheWindowEvenInsideOneZone() {
        var tracker = ZoneTracker(calibration: measured)
        XCTAssertNil(tracker.update(angle: 40, now: t0))
        XCTAssertNil(tracker.update(angle: 30, now: t0 + 0.5))
        XCTAssertNil(tracker.update(angle: 20, now: t0 + 0.9))
        XCTAssertNil(tracker.update(angle: 10, now: t0 + 1.2))    // still moving: no commit
        XCTAssertNil(tracker.update(angle: 10, now: t0 + 1.9))
        XCTAssertEqual(tracker.update(angle: 10, now: t0 + 2.3),  // stopped at 1.2 s, 1 s later
                       ZoneTransition(from: .normal, to: .low, at: t0 + 2.3))
    }

    func testReturningToCommittedZoneCancelsCandidate() {
        var tracker = ZoneTracker(calibration: measured)
        XCTAssertNil(tracker.update(angle: 30, now: t0))
        XCTAssertNil(tracker.update(angle: 115, now: t0 + 0.5))
        XCTAssertNil(tracker.update(angle: 30, now: t0 + 0.6))
        XCTAssertNil(tracker.update(angle: 30, now: t0 + 1.1))    // clock restarted at 0.6
        XCTAssertEqual(tracker.update(angle: 30, now: t0 + 1.6)?.to, .low)
    }

    /// Regression on the defect found by measurement (docs/STATUS.md, item 15):
    /// a normal full close crosses `low` in 1.28 s and must not mute the mic on the way down.
    /// Samples are the real ones from docs/research/closed-test.log.
    func testRealFullCloseNeverEntersLow() {
        let samples: [(TimeInterval, Int)] = [
            (0.000, 110), (0.107, 110), (0.213, 110), (0.319, 110), (0.425, 110),
            (0.532, 110), (0.639, 110), (0.744, 110), (0.849, 110),
            (0.954, 109), (1.059, 103), (1.166, 95), (1.269, 85), (1.374, 59),
            (1.477, 46), (1.584, 33), (1.691, 23), (1.798, 15), (1.904, 11),
            (2.008, 9), (2.110, 8), (2.215, 7), (2.321, 6), (2.429, 6),
            (2.534, 5), (2.641, 4), (2.753, 4),
            (2.866, 0), (2.968, 0), (3.080, 0), (3.184, 0), (3.295, 0),
            (3.406, 0), (3.513, 0), (3.624, 0), (3.728, 0), (3.834, 0),
            (3.940, 0), (4.049, 0), (4.153, 0), (4.264, 0), (4.373, 0),
        ]
        var tracker = ZoneTracker(calibration: measured)
        var transitions: [ZoneTransition] = []
        for (offset, angle) in samples {
            if let transition = tracker.update(angle: angle, now: t0 + offset) {
                transitions.append(transition)
            }
        }
        XCTAssertFalse(transitions.contains { $0.to == .low }, "full close leaked into low: \(transitions)")
        XCTAssertEqual(transitions.map(\.to), [.closed])
    }
}

final class CalibrationSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testKeepsMaximumOverTheWindow() {
        var session = CalibrationSession(startedAt: t0)
        XCTAssertEqual(session.observe(angle: 115, now: t0 + 0.5), .measuring)
        XCTAssertEqual(session.observe(angle: 131, now: t0 + 1.5), .measuring)
        XCTAssertEqual(session.observe(angle: 130, now: t0 + 2.5), .measuring)
        XCTAssertEqual(session.observe(angle: 129, now: t0 + 3.0), .succeeded(maxAngle: 131))
    }

    func testRejectsLidThatWasNotPushed() {
        var session = CalibrationSession(startedAt: t0)
        XCTAssertEqual(session.observe(angle: 80, now: t0 + 1.0), .measuring)
        XCTAssertEqual(session.observe(angle: 89, now: t0 + 3.1), .failed(observedMax: 89))
    }

    func testAcceptsExactlyTheMinimum() {
        var session = CalibrationSession(startedAt: t0)
        XCTAssertEqual(session.observe(angle: 85, now: t0 + 0.5), .measuring)
        XCTAssertEqual(session.observe(angle: 90, now: t0 + 3.0), .succeeded(maxAngle: 90))
    }

    /// The defect found in Block 07: the button was pressed from the working position of this
    /// machine (120°, well above the 90° floor) and the lid never moved, yet 120° was stored as
    /// the stop — making `stop` fire at the angle the user works at.
    func testRejectsWorkingPositionHeldStill() {
        var session = CalibrationSession(startedAt: t0)
        XCTAssertEqual(session.observe(angle: 120, now: t0 + 0.5), .measuring)
        XCTAssertEqual(session.observe(angle: 119, now: t0 + 1.5), .measuring)
        XCTAssertEqual(session.observe(angle: 120, now: t0 + 3.1), .failed(observedMax: 120))
    }

    func testRejectsRiseSmallerThanTheMinimum() {
        var session = CalibrationSession(startedAt: t0)
        XCTAssertEqual(session.observe(angle: 120, now: t0 + 0.5), .measuring)
        XCTAssertEqual(session.observe(angle: 124, now: t0 + 3.1), .failed(observedMax: 124))
    }

    /// The peak counts, not the last sample: hands relax off the stop before the window ends.
    func testCountsThePeakEvenIfTheLidSettlesBack() {
        var session = CalibrationSession(startedAt: t0)
        XCTAssertEqual(session.observe(angle: 118, now: t0 + 0.5), .measuring)
        XCTAssertEqual(session.observe(angle: 131, now: t0 + 1.5), .measuring)
        XCTAssertEqual(session.observe(angle: 126, now: t0 + 3.1), .succeeded(maxAngle: 131))
    }
}

final class CalibrationStorageTests: XCTestCase {
    func testRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "com.quietunit.ajar.tests.\(UUID().uuidString)")!
        XCTAssertEqual(Calibration.load(from: defaults), Calibration())

        var calibration = Calibration()
        calibration.maxAngle = 131
        calibration.lowThreshold = 50
        calibration.save(to: defaults)

        XCTAssertEqual(Calibration.load(from: defaults), calibration)
    }
}
