/// The four states of the lid. Only `low` and `stop` carry actions.
enum Zone: String, Codable, CaseIterable {
    /// Lid shut. Closing a laptop is not a gesture — nothing ever fires here.
    case closed
    /// "Pushed it down, didn't shut it" — I stepped away.
    case low
    /// Working position.
    case normal
    /// "Pushed it all the way back" — hit the hinge stop.
    case stop
}
