import Foundation
import IOKit.hid
import Observation
import os

/// Sensor tuning knobs. One place, because the sensor is hardware and hardware needs tuning.
enum SensorConfig {
    /// 20 Hz: measured 10 Hz leaves 12° gaps mid-movement, visible in a live indicator.
    static let pollInterval: TimeInterval = 1.0 / 20.0
    /// A single failed read is noise; this many in a row (~0.25 s) means the sensor is gone.
    static let readFailureLimit = 5
    /// How often the zone tracker is fed, independent of whether the angle moved. 10 Hz gives
    /// ten samples inside the shortest usable `dwell`; the live indicator reads the sensor
    /// directly and is unaffected by this rate.
    static let zoneTick: TimeInterval = 1.0 / 10.0
}

/// Report parsing, kept pure so it can be tested without hardware.
enum LidAngleReport {
    /// Feature report is `01 <lo> <hi>`, angle is little-endian whole degrees.
    /// Short answers, a foreign report ID, or values no hinge can reach are not angles.
    static func angle(from buffer: [UInt8], length: Int) -> Int? {
        guard length >= 3, buffer.count >= 3, buffer[0] == 1 else { return nil }
        let angle = Int(buffer[1]) | Int(buffer[2]) << 8
        return (0...180).contains(angle) ? angle : nil
    }
}

/// Nil policy: only a streak of failures means "sensor gone", not one bad read.
struct ReadFailureTracker {
    let limit: Int
    private(set) var failures = 0

    /// Returns true when the streak is long enough to report the sensor as absent.
    mutating func failed() -> Bool {
        failures += 1
        return failures >= limit
    }

    mutating func succeeded() {
        failures = 0
    }
}

/// The only layer that touches IOKit. Publishes one angle and nothing else.
@Observable
final class LidAngleReader {
    /// `nil` means the sensor is missing or gone. Compatibility gates read this.
    private(set) var currentAngle: Int?

    @ObservationIgnored private let queue = DispatchQueue(label: "com.quietunit.ajar.sensor")
    @ObservationIgnored private let log = Logger(subsystem: "com.quietunit.ajar", category: "sensor")
    @ObservationIgnored private var manager: IOHIDManager?
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var device: IOHIDDevice?
    @ObservationIgnored private var failures = ReadFailureTracker(limit: SensorConfig.readFailureLimit)

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    /// Nothing tears this down on its own: the timer keeps firing on the sensor queue and the
    /// HID callbacks hold an unretained pointer to `self`, so a released reader means a live
    /// dispatch source over freed memory. Dropping a resumed source also trips libdispatch's
    /// "Invalid dispatch state" assertion — it crashed the smoke test roughly one run in three.
    /// Synchronous on purpose: `stop()` hops to the queue, and by `deinit` there is no `self`
    /// left to hop with.
    deinit {
        timer?.cancel()
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerCancel(manager)
        }
    }

    // MARK: - Sensor queue

    private func startOnQueue() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: 0x20,   // Sensors
            kIOHIDDeviceUsageKey: 0x8A,       // Lid angle
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidAngleReader>.fromOpaque(context).takeUnretainedValue().deviceAppeared(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LidAngleReader>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)

        IOHIDManagerSetDispatchQueue(manager, queue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            log.error("IOHIDManagerOpen failed — no lid angle sensor available")
            publish(nil)
            return
        }
        IOHIDManagerActivate(manager)
        self.manager = manager

        device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
        if device == nil {
            log.notice("no lid angle sensor matched")
            publish(nil)
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: SensorConfig.pollInterval)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        device = nil
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerCancel(manager)
        }
        manager = nil
        publish(nil)
    }

    private func poll() {
        guard let device else { return }   // removal already published nil

        var buffer = [UInt8](repeating: 0, count: 8)
        var length = buffer.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buffer, &length)

        guard result == kIOReturnSuccess,
              let angle = LidAngleReport.angle(from: buffer, length: length) else {
            if failures.failed() {
                log.error("\(SensorConfig.readFailureLimit) failed reads in a row — sensor reported absent")
                publish(nil)
            }
            return
        }
        failures.succeeded()
        publish(angle)
    }

    private func deviceAppeared(_ device: IOHIDDevice) {
        log.notice("lid angle sensor appeared")
        self.device = device
        failures.succeeded()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        log.notice("lid angle sensor removed")
        self.device = nil
        publish(nil)
    }

    private func publish(_ angle: Int?) {
        DispatchQueue.main.async {
            guard self.currentAngle != angle else { return }
            self.currentAngle = angle
        }
    }
}
