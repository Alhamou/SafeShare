import Foundation

/// Tracks *why* the Safe View output is currently blanked.
///
/// Several independent events can demand a blank at the same time (the display sleeps and
/// the session locks, for instance). The output may only be unblanked once **every** reason
/// has been cleared; otherwise waking the display would reveal the lock screen to viewers
/// before the user has actually unlocked.
public struct PrivacyBlankState: Equatable, Sendable {
    /// Active reasons in the order they were raised; the most recent one is displayed.
    public private(set) var reasons: [PrivacyBlankReason] = []

    public init() {}

    public var isBlanked: Bool { !reasons.isEmpty }

    /// The reason that should currently be shown on the output, if any.
    public var displayedReason: PrivacyBlankReason? { reasons.last }

    /// Raises `reason`. Returns the reason to display.
    @discardableResult
    public mutating func raise(_ reason: PrivacyBlankReason) -> PrivacyBlankReason {
        reasons.removeAll { $0 == reason }
        reasons.append(reason)
        return reason
    }

    /// Clears `reason`. Returns the reason that must stay on screen, or `nil` when the output
    /// may be unblanked.
    @discardableResult
    public mutating func clear(_ reason: PrivacyBlankReason) -> PrivacyBlankReason? {
        reasons.removeAll { $0 == reason }
        return reasons.last
    }

    public mutating func clearAll() {
        reasons.removeAll()
    }
}
