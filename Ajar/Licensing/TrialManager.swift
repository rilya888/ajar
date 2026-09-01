import Foundation

enum TrialConfig {
    /// Two weeks, not one: the gesture has to survive a work week and a weekend (PRODUCT.md).
    static let days = 14
    static let defaultsKey = "firstRunDate"
}

/// When the trial started, and what tier that makes us.
///
/// The date is written twice — `UserDefaults` and a file in Application Support — and the
/// *earlier* of the two wins. Neither store survives everything: `defaults delete` wipes one,
/// a cleaner app wipes the other, and whoever restores from a backup gets whichever came back.
/// Taking the minimum means a reinstall keeps the original start date instead of granting a
/// fresh trial. If both are missing this is a first run: today, written to both at once.
///
/// ponytail: turning the clock back beats the trial. Accepted — the price is $9 once, and
/// every line of anti-piracy code is a bug waiting to fire on an honest buyer.
struct TrialManager {
    let defaults: UserDefaults
    let markerURL: URL

    init(defaults: UserDefaults = .standard, markerURL: URL = TrialManager.defaultMarkerURL()) {
        self.defaults = defaults
        self.markerURL = markerURL
    }

    static func defaultMarkerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ajar/first-run", isDirectory: false)
    }

    /// Reads both marks, returns the earlier one, and heals whichever store is missing it.
    @discardableResult
    func firstRun(now: Date = Date()) -> Date {
        let stored = [defaultsMark, fileMark].compactMap { $0 }
        let start = stored.min() ?? now
        if stored.count < 2 { write(start) }
        return start
    }

    func tier(now: Date = Date(), hasLicense: Bool) -> Tier {
        if hasLicense { return .pro }   // a license outlives an expired trial
        let elapsed = now.timeIntervalSince(firstRun(now: now))
        let used = max(0, Int(floor(elapsed / 86_400)))
        return used < TrialConfig.days ? .trial(daysLeft: TrialConfig.days - used) : .free
    }

    private var defaultsMark: Date? {
        guard let seconds = defaults.object(forKey: TrialConfig.defaultsKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private var fileMark: Date? {
        guard let text = try? String(contentsOf: markerURL, encoding: .utf8),
              let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func write(_ date: Date) {
        let seconds = date.timeIntervalSince1970
        defaults.set(seconds, forKey: TrialConfig.defaultsKey)
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? String(seconds).write(to: markerURL, atomically: true, encoding: .utf8)
    }
}
