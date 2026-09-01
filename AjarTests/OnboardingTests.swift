import XCTest
@testable import Ajar

final class OnboardingStateTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnboardingStateTests-\(UUID().uuidString)")!
    }

    func testDefaultsToNotCompleted() {
        XCTAssertFalse(OnboardingState.hasCompleted(in: freshDefaults()))
    }

    func testMarkCompletedPersists() {
        let defaults = freshDefaults()
        XCTAssertFalse(OnboardingState.hasCompleted(in: defaults))
        OnboardingState.markCompleted(in: defaults)
        XCTAssertTrue(OnboardingState.hasCompleted(in: defaults))
    }

    func testSeparateSuitesDontLeakIntoEachOther() {
        let a = freshDefaults()
        let b = freshDefaults()
        OnboardingState.markCompleted(in: a)
        XCTAssertTrue(OnboardingState.hasCompleted(in: a))
        XCTAssertFalse(OnboardingState.hasCompleted(in: b))
    }
}

final class CompatibilityGateTests: XCTestCase {
    func testNoAngleIsIncompatible() {
        XCTAssertFalse(CompatibilityGate.isCompatible(currentAngle: nil))
    }

    func testAnyAngleIsCompatible() {
        XCTAssertTrue(CompatibilityGate.isCompatible(currentAngle: 0))
        XCTAssertTrue(CompatibilityGate.isCompatible(currentAngle: 115))
        XCTAssertTrue(CompatibilityGate.isCompatible(currentAngle: 180))
    }
}
