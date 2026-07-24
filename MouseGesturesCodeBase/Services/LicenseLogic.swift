import Foundation

/// Represents the current license state of the application.
public enum LicenseStatus: String, Codable {
    case trial = "Trial"
    case pro = "Pro"
    case expired = "Expired"
    case free = "Free"
}

/// Pure, dependency-free licensing rules.
///
/// This is the single source of truth for trial-day math and Pro-feature gating.
/// It deliberately depends on nothing but `Foundation` (no StoreKit, UserDefaults,
/// notifications, or UI), so it can be unit-tested in isolation. `LicenseService`
/// wires these rules to persisted state and the purchase layer.
public enum LicenseLogic {

    /// Length of the free Pro trial, in days.
    public static let trialDurationDays = 30

    /// Computes the trial status for a given first-launch date.
    ///
    /// - Parameters:
    ///   - firstLaunch: The date the trial began (first launch).
    ///   - now: The current date.
    ///   - durationDays: Trial length in days (defaults to ``trialDurationDays``).
    ///   - calendar: Calendar used for the day math (defaults to `.current`).
    /// - Returns: `.trial` with the number of whole days remaining while still inside
    ///   the trial window, otherwise `.expired` with `0` remaining.
    public static func trialStatus(firstLaunch: Date,
                                   now: Date,
                                   durationDays: Int = trialDurationDays,
                                   calendar: Calendar = .current) -> (status: LicenseStatus, remaining: Int) {
        let components = calendar.dateComponents([.day], from: firstLaunch, to: now)
        // Clamp elapsed days to be non-negative. If `now` precedes `firstLaunch`
        // (clock skew, a rolled-back clock that slipped past the high-water-mark
        // clamp, or a corrupted/cleared high-water mark), a negative elapsed count
        // makes `durationDays - daysElapsed` exceed the full trial length —
        // effectively *extending* the trial past its duration. Treating any such
        // case as day 0 guarantees the trial can never report more than
        // `durationDays` remaining, no matter what date arrives.
        let daysElapsed = max(0, components.day ?? 0)

        if daysElapsed < durationDays {
            return (.trial, durationDays - daysElapsed)
        } else {
            return (.expired, 0)
        }
    }

    /// Whether the given status unlocks Pro features. Pro purchases and active trials qualify.
    public static func allowsProFeatures(_ status: LicenseStatus) -> Bool {
        return status == .pro || status == .trial
    }
}
