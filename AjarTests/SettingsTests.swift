import XCTest
@testable import Ajar

final class CalibrationValidationTests: XCTestCase {
    func testDefaultUncalibratedIsValid() {
        XCTAssertTrue(Calibration().isValid)
    }

    func testCalibratedWithRoomToSpareIsValid() {
        XCTAssertTrue(Calibration(maxAngle: 131).isValid)
    }

    func testLowThresholdAtOrBelowClosedIsInvalid() {
        XCTAssertFalse(Calibration(closedBelow: 10, lowThreshold: 10).isValid)
        XCTAssertFalse(Calibration(closedBelow: 10, lowThreshold: 5).isValid)
        XCTAssertTrue(Calibration(closedBelow: 10, lowThreshold: 11).isValid)
    }

    func testNegativeHysteresisIsInvalid() {
        XCTAssertFalse(Calibration(hysteresis: -1).isValid)
        XCTAssertTrue(Calibration(hysteresis: 0).isValid)
    }

    func testNonPositiveDwellIsInvalid() {
        XCTAssertFalse(Calibration(dwell: 0).isValid)
        XCTAssertFalse(Calibration(dwell: -1).isValid)
    }

    func testLowThresholdAtOrPastStopStartIsInvalid() {
        // maxAngle 131, stopMargin 2 -> stop starts at 129.
        XCTAssertTrue(Calibration(maxAngle: 131, lowThreshold: 126, hysteresis: 2).isValid)   // 128 < 129
        XCTAssertFalse(Calibration(maxAngle: 131, lowThreshold: 127, hysteresis: 2).isValid)  // 129 == 129
        XCTAssertFalse(Calibration(maxAngle: 131, lowThreshold: 128, hysteresis: 2).isValid)  // 130 > 129
    }

    func testHysteresisAloneCanPushLowIntoStop() {
        // lowThreshold itself is fine; widening it with hysteresis collides with stop.
        XCTAssertTrue(Calibration(maxAngle: 131, lowThreshold: 100, hysteresis: 5).isValid)
        XCTAssertFalse(Calibration(maxAngle: 131, lowThreshold: 100, hysteresis: 30).isValid)
    }

    func testUncalibratedSkipsTheStopCheck() {
        // No maxAngle: stop doesn't exist yet, so any lowThreshold above closedBelow is fine.
        XCTAssertTrue(Calibration(maxAngle: nil, lowThreshold: 170, hysteresis: 20).isValid)
    }
}

final class AngleDisplaySmootherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    func testHoldsInitialValueUntilNewReadingSettles() {
        var smoother = AngleDisplaySmoother()
        XCTAssertNil(smoother.update(angle: 120, now: t0))
        XCTAssertNil(smoother.update(angle: 120, now: t0 + 0.2))
        XCTAssertEqual(smoother.update(angle: 120, now: t0 + 0.35), 120)
    }

    func testIgnoresBriefFlickerBackAndForth() {
        var smoother = AngleDisplaySmoother(displayed: 119)
        XCTAssertEqual(smoother.update(angle: 120, now: t0), 119)           // candidate just started
        XCTAssertEqual(smoother.update(angle: 119, now: t0 + 0.1), 119)     // flipped back: no change committed
        XCTAssertEqual(smoother.update(angle: 120, now: t0 + 0.2), 119)     // flipped again: clock restarts
        XCTAssertEqual(smoother.update(angle: 120, now: t0 + 0.55), 120)    // finally held 0.3 s
    }

    func testSensorGoingAwayClearsImmediately() {
        var smoother = AngleDisplaySmoother(displayed: 115)
        XCTAssertNil(smoother.update(angle: nil, now: t0))
    }

    func testReappearingSensorNeedsFreshHoldTime() {
        var smoother = AngleDisplaySmoother(displayed: 115)
        _ = smoother.update(angle: nil, now: t0)
        XCTAssertNil(smoother.update(angle: 60, now: t0 + 0.1))
        XCTAssertEqual(smoother.update(angle: 60, now: t0 + 0.45), 60)
    }
}
