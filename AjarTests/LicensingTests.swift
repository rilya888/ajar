import XCTest
@testable import Ajar

private let day: TimeInterval = 86_400

final class TrialManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var markerURL: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TrialManagerTests-\(UUID().uuidString)")!
        markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrialManagerTests-\(UUID().uuidString)/first-run")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: markerURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func manager() -> TrialManager {
        TrialManager(defaults: defaults, markerURL: markerURL)
    }

    private func seed(defaultsDate: Date? = nil, fileDate: Date? = nil) {
        if let defaultsDate {
            defaults.set(defaultsDate.timeIntervalSince1970, forKey: TrialConfig.defaultsKey)
        }
        if let fileDate {
            try? FileManager.default.createDirectory(
                at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? String(fileDate.timeIntervalSince1970).write(to: markerURL, atomically: true, encoding: .utf8)
        }
    }

    func testNoMarksMeansTodayWrittenToBoth() {
        XCTAssertEqual(manager().firstRun(now: now), now)
        XCTAssertEqual(defaults.double(forKey: TrialConfig.defaultsKey), now.timeIntervalSince1970, accuracy: 0.001)
        let text = try? String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertEqual(Double(text ?? ""), now.timeIntervalSince1970)
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .trial(daysLeft: 14))
    }

    func testThirteenDaysLeavesOneDay() {
        seed(defaultsDate: now.addingTimeInterval(-13 * day), fileDate: now.addingTimeInterval(-13 * day))
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .trial(daysLeft: 1))
    }

    func testJustUnderFourteenDaysIsStillTrial() {
        seed(defaultsDate: now.addingTimeInterval(-14 * day + 1), fileDate: now.addingTimeInterval(-14 * day + 1))
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .trial(daysLeft: 1))
    }

    func testExactlyFourteenDaysIsFree() {
        seed(defaultsDate: now.addingTimeInterval(-14 * day), fileDate: now.addingTimeInterval(-14 * day))
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .free)
    }

    func testLicenseBeatsExpiredTrial() {
        seed(defaultsDate: now.addingTimeInterval(-400 * day), fileDate: now.addingTimeInterval(-400 * day))
        XCTAssertEqual(manager().tier(now: now, hasLicense: true), .pro)
    }

    func testLicenseBeatsRunningTrialToo() {
        seed(defaultsDate: now, fileDate: now)
        XCTAssertEqual(manager().tier(now: now, hasLicense: true), .pro)
    }

    /// The reinstall case: one store was wiped and came back with a fresh date.
    func testEarlierOfTheTwoMarksWins() {
        seed(defaultsDate: now.addingTimeInterval(-20 * day), fileDate: now.addingTimeInterval(-2 * day))
        XCTAssertEqual(manager().firstRun(now: now), now.addingTimeInterval(-20 * day))
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .free)
    }

    func testEarlierOfTheTwoMarksWinsTheOtherWayRound() {
        seed(defaultsDate: now.addingTimeInterval(-2 * day), fileDate: now.addingTimeInterval(-20 * day))
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .free)
    }

    func testMissingFileIsHealedFromDefaults() {
        seed(defaultsDate: now.addingTimeInterval(-5 * day))
        XCTAssertEqual(manager().firstRun(now: now), now.addingTimeInterval(-5 * day))
        let text = try? String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertEqual(Double(text ?? ""), now.addingTimeInterval(-5 * day).timeIntervalSince1970)
    }

    func testMissingDefaultsIsHealedFromFile() {
        seed(fileDate: now.addingTimeInterval(-5 * day))
        XCTAssertEqual(manager().firstRun(now: now), now.addingTimeInterval(-5 * day))
        XCTAssertEqual(
            defaults.double(forKey: TrialConfig.defaultsKey),
            now.addingTimeInterval(-5 * day).timeIntervalSince1970, accuracy: 0.001
        )
    }

    func testGarbageInTheFileIsIgnoredNotFatal() {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? "not a date".write(to: markerURL, atomically: true, encoding: .utf8)
        seed(defaultsDate: now.addingTimeInterval(-3 * day))
        XCTAssertEqual(manager().firstRun(now: now), now.addingTimeInterval(-3 * day))
    }

    /// Clock pushed into the future then back: elapsed goes negative, the trial doesn't wrap.
    func testFutureFirstRunDateStillGivesAFullTrial() {
        seed(defaultsDate: now.addingTimeInterval(10 * day), fileDate: now.addingTimeInterval(10 * day))
        XCTAssertEqual(manager().tier(now: now, hasLicense: false), .trial(daysLeft: 14))
    }
}

/// Fixed fixtures, signed once with a throwaway Ed25519 pair whose private half was never
/// stored anywhere. Passed explicitly as `publicKeyBase64` so these stay valid independent of
/// whatever real key `LicenseVerifier.publicKeyBase64` carries. No network anywhere in this
/// file: the offline scheme has none to reach.
final class LicenseVerifierTests: XCTestCase {
    private let fixtureKey = "z8Fm18TbQT6gY/g69mHQathxVtlIeOSQq+drSHcgD6o="

    // payload "buyer@example.com|ord_1042"
    private let valid = "YnV5ZXJAZXhhbXBsZS5jb218b3JkXzEwNDI=.MAVdQ58GM9RfJNDmBrhGklQATUXe84sdxDaqvbFnqZU+t2rMfO/KizTpA9z3MaPpZa3DouNRMT0XPfehrT1uCA=="
    // payload "someone.else@example.com|ord_2077"
    private let otherBuyer = "c29tZW9uZS5lbHNlQGV4YW1wbGUuY29tfG9yZF8yMDc3.sfb+PmQBFa+O0NeE1qVtitUKW105YoN9QcuOndYo2hnkTFim12jIYT+nErNl/HUPS+bOnS4G3/ag7iqAqkoxCw=="
    // same payload, signed with a different private key
    private let foreignSignature = "YnV5ZXJAZXhhbXBsZS5jb218b3JkXzEwNDI=.SmHIqROBi+OKOTmipWtedIM64zudpDy9Ab2YM7Dc4PCsi6ZyYXyzWeIYrRAwwBaSugiGmJBOJi9vOMhZB0UcBg=="
    // our own signature, but lifted from the *other* payload and pasted onto this one
    private let swappedSignature = "YnV5ZXJAZXhhbXBsZS5jb218b3JkXzEwNDI=.4W+Sesrh0Vk7XDrzSNRx/wohR+MMq+NWeotrNhe2UVx48KEWRffSSG2l4bVo512BV5HKBYC73C/XMkujIycYBQ=="
    // correctly signed, but the payload has no order id
    private let noOrderID = "YnV5ZXJAZXhhbXBsZS5jb20=.hwtUZIw1VdWqrqfl3t3lnGfqYXOTV3rCi8rcNujnnRaTQuLAKF3xvOXLDkrM47foKRv3uBzIJ95glsJXcrQIBA=="

    private func expectFailure(_ key: String, _ expected: LicenseError, line: UInt = #line) {
        XCTAssertThrowsError(try LicenseVerifier.verify(key, publicKeyBase64: fixtureKey), line: line) { error in
            XCTAssertEqual(error as? LicenseError, expected, line: line)
        }
    }

    func testValidKeyReturnsTheEmail() throws {
        XCTAssertEqual(try LicenseVerifier.verify(valid, publicKeyBase64: fixtureKey), "buyer@example.com")
        XCTAssertEqual(
            try LicenseVerifier.verify(otherBuyer, publicKeyBase64: fixtureKey), "someone.else@example.com"
        )
    }

    /// Copy-pasting out of a mail client brings whitespace along.
    func testSurroundingWhitespaceIsTolerated() throws {
        XCTAssertEqual(try LicenseVerifier.verify("  \n\(valid)\n ", publicKeyBase64: fixtureKey), "buyer@example.com")
    }

    func testSignatureFromAnotherKeyIsRejected() {
        expectFailure(foreignSignature, .badSignature)
    }

    func testSignatureLiftedFromAnotherPayloadIsRejected() {
        expectFailure(swappedSignature, .badSignature)
    }

    func testFlippedCharacterInThePayloadIsRejected() {
        // "buyer" → "buzer": still valid base64, no longer what was signed
        expectFailure("YnV6ZXJAZXhhbXBsZS5jb218b3JkXzEwNDI=." + valid.split(separator: ".")[1], .badSignature)
    }

    func testEmptyKeyIsUnreadable() {
        expectFailure("", .unreadableKey)
        expectFailure("   ", .unreadableKey)
    }

    func testMissingSeparatorIsUnreadable() {
        expectFailure(String(valid.split(separator: ".")[0]), .unreadableKey)
    }

    func testExtraSeparatorIsUnreadable() {
        expectFailure(valid + ".extra", .unreadableKey)
    }

    func testNonBase64IsUnreadable() {
        expectFailure("not-base64!.also-not-base64!", .unreadableKey)
    }

    func testPayloadWithoutOrderIDIsUnreadable() {
        expectFailure(noOrderID, .unreadableKey)
    }

    func testPayloadWithEmptyEmailIsUnreadable() {
        let payload = Data("|ord_1042".utf8).base64EncodedString()
        expectFailure(payload + "." + valid.split(separator: ".")[1], .unreadableKey)
    }

    /// A key valid against a different build's public key must not slip through.
    func testAnotherPublicKeyDoesNotValidateOurFixture() {
        XCTAssertThrowsError(
            try LicenseVerifier.verify(
                valid, publicKeyBase64: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            )
        )
    }

    func testEveryErrorHasAMessage() {
        XCTAssertNotEqual(LicenseError.unreadableKey.errorDescription, LicenseError.badSignature.errorDescription)
        XCTAssertFalse(LicenseError.unreadableKey.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(LicenseError.badSignature.errorDescription?.isEmpty ?? true)
    }
}

final class GestureCounterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountsWithinTheWindow() {
        var counter = GestureCounter(weekStart: now, count: 0)
        counter.record(now: now)
        counter.record(now: now.addingTimeInterval(3 * day))
        XCTAssertEqual(counter.count(now: now.addingTimeInterval(3 * day)), 2)
    }

    func testWindowRollsOverAfterSevenDays() {
        var counter = GestureCounter(weekStart: now, count: 40)
        counter.record(now: now.addingTimeInterval(7 * day))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(counter.weekStart, now.addingTimeInterval(7 * day))
    }

    func testStaleCountReadsAsZeroWithoutBeingRecorded() {
        let counter = GestureCounter(weekStart: now, count: 40)
        XCTAssertEqual(counter.count(now: now.addingTimeInterval(8 * day)), 0)
    }

    func testClockGoingBackwardsRestartsTheWindow() {
        var counter = GestureCounter(weekStart: now, count: 40)
        counter.record(now: now.addingTimeInterval(-day))
        XCTAssertEqual(counter.count, 1)
    }

    func testRoundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "GestureCounterTests-\(UUID().uuidString)")!
        XCTAssertEqual(GestureCounter.load(from: defaults).count, 0)
        GestureCounter(weekStart: now, count: 7).save(to: defaults)
        XCTAssertEqual(GestureCounter.load(from: defaults), GestureCounter(weekStart: now, count: 7))
    }
}

// Stage 1 (free-first): the popover upsell line is gone, so UpsellLineTests went with it.
// GestureCounter itself stays under test above — it's pure logic Block 13 re-attaches.
