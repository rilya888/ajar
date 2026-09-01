import XCTest
@testable import Ajar

private let live = MicState(method: .mute, value: 0)
private let muted = MicState(method: .mute, value: 1)

/// The four combinations of "was off / was on" × "user interfered / did not".
final class MuteRestoreStateTests: XCTestCase {
    func testWasLiveAndUntouchedIsRestored() {
        var state = MuteRestoreState()
        XCTAssertEqual(state.enter(current: live), muted)
        XCTAssertEqual(state.exit(current: muted), live)
    }

    func testWasLiveButUserUnmutedMeanwhileIsLeftAlone() {
        var state = MuteRestoreState()
        XCTAssertEqual(state.enter(current: live), muted)
        XCTAssertNil(state.exit(current: live))
    }

    func testWasMutedByUserIsNeverTouched() {
        var state = MuteRestoreState()
        XCTAssertNil(state.enter(current: muted))
        XCTAssertNil(state.exit(current: muted))
    }

    func testWasMutedByUserWhoUnmutedMeanwhileStaysUnmuted() {
        var state = MuteRestoreState()
        XCTAssertNil(state.enter(current: muted))
        XCTAssertNil(state.exit(current: live))
    }

    func testSecondExitWithoutEnterDoesNothing() {
        var state = MuteRestoreState()
        XCTAssertEqual(state.enter(current: live), muted)
        XCTAssertEqual(state.exit(current: muted), live)
        XCTAssertNil(state.exit(current: muted))
    }

    // MARK: - Volume fallback

    func testVolumeFallbackRestoresTheExactPreviousScalar() {
        let before = MicState(method: .volume, value: 0.73)
        var state = MuteRestoreState()
        XCTAssertEqual(state.enter(current: before), MicState(method: .volume, value: 0))
        XCTAssertEqual(state.exit(current: MicState(method: .volume, value: 0)), before)
    }

    func testVolumeFallbackLeavesAUserRaisedLevelAlone() {
        var state = MuteRestoreState()
        _ = state.enter(current: MicState(method: .volume, value: 0.73))
        XCTAssertNil(state.exit(current: MicState(method: .volume, value: 0.5)))
    }

    func testVolumeAtZeroCountsAsAlreadySilent() {
        var state = MuteRestoreState()
        XCTAssertNil(state.enter(current: MicState(method: .volume, value: 0)))
    }

    /// A rounded read-back is not the user's doing.
    func testTinyScalarDriftStillCountsAsOurOwnValue() {
        let before = MicState(method: .volume, value: 0.73)
        var state = MuteRestoreState()
        _ = state.enter(current: before)
        XCTAssertEqual(state.exit(current: MicState(method: .volume, value: 0.0001)), before)
    }

    /// Device swapped mid-gesture and the new one only does volume: nothing of ours applies.
    func testMethodChangeMidGestureIsLeftAlone() {
        var state = MuteRestoreState()
        _ = state.enter(current: live)
        XCTAssertNil(state.exit(current: MicState(method: .volume, value: 0)))
    }

    func testForgetDropsTheIntervention() {
        var state = MuteRestoreState()
        _ = state.enter(current: live)
        state.forget()
        XCTAssertNil(state.exit(current: muted))
    }
}
