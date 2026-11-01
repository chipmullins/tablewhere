import SwiftUI

/// ForkRoad's haptic vocabulary, so every kind of interaction feels the same
/// wherever it happens. Use with `.sensoryFeedback(_:trigger:)`; for a tap
/// that doesn't change observable state, bump a local counter in the action
/// and use that as the trigger.
enum Haptic {
    /// Toggles, chips, segmented changes, heart / bookmark, checking a row, voting.
    static let tick: SensoryFeedback = .selection
    /// Primary commits: Lock it in, Start group, Add place, Send the plan.
    static let commit: SensoryFeedback = .impact(weight: .medium)
    /// A decision landed: the spin's pick, the group's winner.
    static let decided: SensoryFeedback = .success
    /// Destructive: blacklist, remove.
    static let destructive: SensoryFeedback = .impact(flexibility: .soft)
}
