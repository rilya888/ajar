import CoreAudio
import Foundation
import os

/// The only layer that touches CoreAudio. Silences the default input on the lid gesture
/// and puts it back exactly as it was. All decisions live in `MuteRestoreState`.
final class MicMuter {
    private let log = Logger(subsystem: "com.quietunit.ajar", category: "mic")
    private var state = MuteRestoreState()

    /// The device we silenced. Remembered because the user may switch inputs mid-gesture
    /// (plugs in a headset): we un-mute what we muted, not whatever is default by then.
    private var target: AudioObjectID?

    /// Which path the current input actually took. Onboarding text depends on it.
    private(set) var method: MuteMethod?

    func mute() {
        guard let device = defaultInputDevice() else {
            log.error("no default input device — nothing to mute")
            return
        }
        guard let current = read(device) else {
            log.error("input device exposes neither settable mute nor volume")
            return
        }
        method = current.method
        target = device
        guard let apply = state.enter(current: current) else {
            log.notice("input already silent — left alone")
            return
        }
        write(apply, to: device)
    }

    func restore() {
        guard let device = target else { return }
        target = nil
        guard let current = read(device) else {
            state.forget()   // device went away while the lid was down
            return
        }
        guard let apply = state.exit(current: current) else { return }
        write(apply, to: device)
    }

    // MARK: - CoreAudio

    private func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func defaultInputDevice() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// Mute first, volume as the fallback — some inputs have no mute property at all.
    private func read(_ device: AudioObjectID) -> MicState? {
        var mute = address(kAudioDevicePropertyMute)
        if writable(device, &mute) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &value) == noErr {
                return MicState(method: .mute, value: value == 0 ? 0 : 1)
            }
        }
        var volume = address(kAudioDevicePropertyVolumeScalar)
        if writable(device, &volume) {
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &volume, 0, nil, &size, &value) == noErr {
                return MicState(method: .volume, value: Float(value))
            }
        }
        return nil
    }

    /// Present *and* settable: a read-only mute property would look like a working path
    /// and silently do nothing, leaving the user believing the mic is off.
    private func writable(_ device: AudioObjectID, _ addr: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &addr)
            && AudioObjectIsPropertySettable(device, &addr, &settable) == noErr
            && settable.boolValue
    }

    private func write(_ state: MicState, to device: AudioObjectID) {
        var status = noErr
        switch state.method {
        case .mute:
            var addr = address(kAudioDevicePropertyMute)
            var value = UInt32(state.value == 0 ? 0 : 1)
            status = AudioObjectSetPropertyData(
                device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        case .volume:
            var addr = address(kAudioDevicePropertyVolumeScalar)
            var value = Float32(state.value)
            status = AudioObjectSetPropertyData(
                device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
        if status != noErr {
            log.error("failed to write \(state.method.rawValue, privacy: .public): OSStatus \(status)")
        }
    }
}
