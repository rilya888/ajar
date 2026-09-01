import Foundation
import Observation

/// Root of the app's observable state: sensor → zones → actions.
@Observable
final class AppState {
    let sensor = LidAngleReader()
    let suppressor = Suppressor()
    let shortcuts = ShortcutRunner()
    let license = LicenseManager()

    @ObservationIgnored private let mic = MicMuter()
    @ObservationIgnored private let trial = TrialManager()
    @ObservationIgnored private var tracker = ZoneTracker(calibration: .load())
    @ObservationIgnored private var bindings = ShortcutBindings.load()
    @ObservationIgnored private var zoneTimer: Timer?
    /// The onboarding window, typed `AnyObject` so this file doesn't need `import AppKit`.
    /// Held here so the window survives past the call that opened it. Managed by the
    /// `AppState` extension in `UI/OnboardingView.swift`.
    @ObservationIgnored var onboardingWindow: AnyObject?

    private(set) var zone: Zone = .normal
    /// Observed, not ignored: the upsell line in the popover moves with it.
    private var gestures = GestureCounter.load()

    /// ponytail: Stage 1 (free-first, docs/PRODUCT.md "Этапы выпуска") — payment provider
    /// isn't ready, so the app ships free with everything unlocked. This pins `tier` to `.pro`
    /// and the payment/trial UI is hidden. Block 13 flips this back to `false` to restore the
    /// real logic below (`trial.tier(hasLicense:)`).
    static let proUnlockedForFreeStage = true

    /// The one source of truth for gates. Reading it tracks `license.email`, so activating a
    /// key unlocks the UI without a restart.
    var tier: Tier {
        if Self.proUnlockedForFreeStage { return .pro }
        return trial.tier(hasLicense: license.hasLicense)
    }

    var gesturesThisWeek: Int { gestures.count(now: Date()) }

    /// Settings writes here directly: takes effect on the next sample, no restart, and persists.
    var calibration: Calibration {
        get { tracker.calibration }
        set {
            tracker.calibration = newValue
            newValue.save()
        }
    }

    /// Same shape as `calibration`: Settings edits this directly, it takes effect on the next
    /// transition and persists. Free-tier gating happens in the Settings UI, not here — Tier is
    /// the one source of truth for gates (ARCHITECTURE.md), so this layer doesn't duplicate it.
    var shortcutBindings: ShortcutBindings {
        get { bindings }
        set {
            bindings = newValue
            newValue.save()
        }
    }

    /// Reading `graceRevision` is what makes SwiftUI redraw when a timed grace ends.
    var menuBar: MenuBarViewModel {
        _ = suppressor.graceRevision
        return MenuBarViewModel(
            angle: sensor.currentAngle,
            zone: zone,
            suppression: suppressor.state(zone: zone),
            tier: tier,
            shortcutError: shortcuts.lastError,
            gesturesThisWeek: gesturesThisWeek
        )
    }

    init() {
        trial.firstRun()   // first launch starts the clock, later launches just heal the marks
        sensor.start()
        startZoneTicks()
    }

    deinit { zoneTimer?.invalidate() }

    /// The tracker is driven by a clock, not by angle changes.
    ///
    /// The gesture this product sells is *holding the lid still*, and a still lid publishes
    /// nothing — `LidAngleReader` only reports changes. Driven by changes, `dwell` could never
    /// elapse on its own: the zone committed at the first sample after the hold, which is the
    /// moment the user starts moving the lid again. Measured on hardware 2026-08-12
    /// (docs/research/gesture-2026-08-12.log): the lid stopped at 14° and the mute fired 12.6 s
    /// later, as the lid was being reopened, and the matching restore never fired at all because
    /// the lid then stopped once more — leaving the microphone muted indefinitely.
    private func startZoneTicks() {
        let timer = Timer(timeInterval: SensorConfig.zoneTick, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.handle(angle: self.sensor.currentAngle)
        }
        // .common, not the default mode: an open menu bar popover puts the run loop into event
        // tracking, where a default-mode timer stops firing — precisely while the user watches.
        RunLoop.main.add(timer, forMode: .common)
        zoneTimer = timer
    }

    private func handle(angle: Int?) {
        guard let angle else { return }   // sensor gone: hold the zone, do nothing
        let now = Date()
        guard let transition = tracker.update(angle: angle, now: now) else { return }
        zone = transition.to

        // Suppression gates actions only — the sensor keeps reading and the UI keeps updating.
        let suppressed = suppressor.isSuppressed(zone: transition.to, now: now)
        switch ZoneAction.decide(transition, suppressed: suppressed) {
        case .mute:
            mic.mute()
            gestures.record(now: now)   // the number the upsell line names
            gestures.save()
        case .restore: mic.restore()
        case .none: break
        }

        for name in ShortcutAction.decide(transition, bindings: bindings, tier: tier, suppressed: suppressed) {
            shortcuts.run(name)
        }
    }
}
