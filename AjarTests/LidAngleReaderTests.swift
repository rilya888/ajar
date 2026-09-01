import XCTest
@testable import Ajar

final class LidAngleReportTests: XCTestCase {
    func testParsesMeasuredReport() {
        // 115° on the dev machine: 01 73 00
        XCTAssertEqual(LidAngleReport.angle(from: [0x01, 0x73, 0x00, 0, 0, 0, 0, 0], length: 3), 115)
    }

    func testParsesClosedLid() {
        XCTAssertEqual(LidAngleReport.angle(from: [0x01, 0x00, 0x00, 0, 0, 0, 0, 0], length: 3), 0)
    }

    func testRejectsShortAnswer() {
        XCTAssertNil(LidAngleReport.angle(from: [0x01, 0x73, 0x00, 0, 0, 0, 0, 0], length: 2))
        XCTAssertNil(LidAngleReport.angle(from: [0x01], length: 1))
        XCTAssertNil(LidAngleReport.angle(from: [], length: 0))
    }

    func testRejectsForeignReportID() {
        XCTAssertNil(LidAngleReport.angle(from: [0x02, 0x73, 0x00, 0, 0, 0, 0, 0], length: 3))
    }

    func testRejectsImpossibleAngle() {
        XCTAssertNil(LidAngleReport.angle(from: [0x01, 0xFF, 0xFF, 0, 0, 0, 0, 0], length: 3))
        XCTAssertNil(LidAngleReport.angle(from: [0x01, 0xB5, 0x00, 0, 0, 0, 0, 0], length: 3))  // 181°
    }
}

final class ReadFailureTrackerTests: XCTestCase {
    func testSingleFailureIsNotAbsence() {
        var tracker = ReadFailureTracker(limit: 5)
        XCTAssertFalse(tracker.failed())
    }

    func testFailuresBelowLimitAreNotAbsence() {
        var tracker = ReadFailureTracker(limit: 5)
        for _ in 1..<5 { XCTAssertFalse(tracker.failed()) }
    }

    func testLimitReachedReportsAbsence() {
        var tracker = ReadFailureTracker(limit: 5)
        for _ in 1..<5 { _ = tracker.failed() }
        XCTAssertTrue(tracker.failed())
    }

    func testSuccessResetsStreak() {
        var tracker = ReadFailureTracker(limit: 3)
        _ = tracker.failed()
        _ = tracker.failed()
        tracker.succeeded()
        XCTAssertFalse(tracker.failed())
        XCTAssertFalse(tracker.failed())
        XCTAssertTrue(tracker.failed())
    }
}
