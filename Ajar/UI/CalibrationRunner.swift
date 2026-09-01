import Foundation
import Observation

/// Drives a `CalibrationSession` off the live sensor for the Settings "Calibrate maximum"
/// button. Polls at 10 Hz rather than subscribing to the sensor: the session only needs a few
/// samples over its 3 s window, and polling keeps this file free of `AppState` observation.
@Observable
final class CalibrationRunner {
    private(set) var outcome: CalibrationSession.Outcome?
    var isRunning: Bool { session != nil }

    @ObservationIgnored private var session: CalibrationSession?
    @ObservationIgnored private var timer: Timer?

    func start(reading angle: @escaping () -> Int?) {
        session = CalibrationSession(startedAt: Date())
        outcome = .measuring
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, let currentAngle = angle(), var session = self.session else { return }
            let outcome = session.observe(angle: currentAngle, now: Date())
            self.session = session
            self.outcome = outcome
            guard case .measuring = outcome else {
                timer.invalidate()
                self.session = nil
                return
            }
        }
    }

    deinit { timer?.invalidate() }
}
