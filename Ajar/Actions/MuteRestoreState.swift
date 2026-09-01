import Foundation

/// How an input device can be silenced. Not every device exposes `mute`, hence the fallback.
enum MuteMethod: String, Equatable {
    case mute
    case volume
}

/// One reading of the input device, in the units of whichever method works on it:
/// `mute` — 0 live / 1 muted, `volume` — scalar 0…1.
struct MicState: Equatable {
    var method: MuteMethod
    var value: Float

    var isSilent: Bool {
        switch method {
        case .mute: value != 0
        case .volume: value <= 0
        }
    }

    /// The value we would write to silence this device.
    var silenced: MicState { MicState(method: method, value: method == .mute ? 1 : 0) }

    /// CoreAudio hands volume back as a rounded scalar; exact float equality would read as
    /// "the user touched it" when nobody did.
    func matches(_ other: MicState) -> Bool {
        method == other.method && abs(value - other.value) < 0.001
    }
}

/// Honest restore, kept away from CoreAudio so every case is testable without a microphone.
/// We put back only what we changed ourselves, and only if it is still how we left it.
struct MuteRestoreState: Equatable {
    private struct Intervention: Equatable {
        let before: MicState
        let applied: MicState
    }

    private var intervention: Intervention?

    /// Entering the gesture zone. Returns what to write, or nil to leave the device alone.
    mutating func enter(current: MicState) -> MicState? {
        guard !current.isSilent else {
            intervention = nil   // already off by the user's hand — not ours to touch or restore
            return nil
        }
        let applied = current.silenced
        intervention = Intervention(before: current, applied: applied)
        return applied
    }

    /// Leaving the gesture zone. Returns what to write, or nil when there is nothing of ours
    /// to undo — either we never intervened, or the user changed the device meanwhile.
    mutating func exit(current: MicState) -> MicState? {
        defer { intervention = nil }
        guard let intervention, current.matches(intervention.applied) else { return nil }
        return intervention.before
    }

    /// Drop the memory of our intervention without writing anything (device disappeared).
    mutating func forget() {
        intervention = nil
    }
}
