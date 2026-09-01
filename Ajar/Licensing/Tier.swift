/// Single source of truth for UI gates. The managers that compute it land in Block 09.
enum Tier: Equatable {
    case trial(daysLeft: Int)
    case free
    case pro

    /// Trial is "everything", so gating asks this, never the case itself.
    var unlocksPro: Bool { self != .free }
}
