import Foundation

/// How many times the lid gesture fired in the current 7-day window.
///
/// This is what the upsell line names ("You've used the lid gesture 40 times this week"),
/// because the honest pitch is the thing the user already does — not a countdown (PRODUCT.md).
/// It is not usage history: two numbers, overwritten in place, never sent anywhere.
struct GestureCounter: Codable, Equatable {
    var weekStart: Date
    var count: Int

    static let window: TimeInterval = 7 * 86_400

    init(weekStart: Date = Date(), count: Int = 0) {
        self.weekStart = weekStart
        self.count = count
    }

    /// Reading and writing both roll the window, so a Mac left alone for a month reports 0
    /// instead of last month's number.
    func count(now: Date) -> Int {
        now.timeIntervalSince(weekStart) < Self.window ? count : 0
    }

    mutating func record(now: Date) {
        if now.timeIntervalSince(weekStart) >= Self.window || now < weekStart {
            weekStart = now
            count = 0
        }
        count += 1
    }
}

extension GestureCounter {
    static let defaultsKey = "gestureCounter"

    static func load(from defaults: UserDefaults = .standard) -> GestureCounter {
        guard let data = defaults.data(forKey: defaultsKey),
              let counter = try? JSONDecoder().decode(GestureCounter.self, from: data) else {
            return GestureCounter()
        }
        return counter
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
