import XCTest

/// Smoke tests for the pure licensing rules in `LicenseLogic`.
///
/// These exercise the exact trial-day math and Pro-gating that `LicenseService`
/// runs in production, but without StoreKit / UserDefaults / notification side
/// effects, so they are deterministic and fast.
final class LicenseLogicTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        return cal.date(from: c)!
    }

    func testDayZeroIsTrialWithFullDuration() {
        let start = date(2026, 1, 1)
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: start, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .trial)
        XCTAssertEqual(r.remaining, 30)
    }

    func testMidTrialCountsDownRemaining() {
        let start = date(2026, 1, 1)
        let now = date(2026, 1, 11) // 10 whole days elapsed
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: now, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .trial)
        XCTAssertEqual(r.remaining, 20)
    }

    func testLastDayStillTrial() {
        let start = date(2026, 1, 1)
        let now = date(2026, 1, 30) // 29 days elapsed, still inside the 30-day window
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: now, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .trial)
        XCTAssertEqual(r.remaining, 1)
    }

    func testBoundaryDayExpires() {
        let start = date(2026, 1, 1)
        let now = date(2026, 1, 31) // exactly 30 days elapsed -> expired
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: now, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .expired)
        XCTAssertEqual(r.remaining, 0)
    }

    func testWellPastTrialExpires() {
        let start = date(2026, 1, 1)
        let now = date(2026, 3, 1)
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: now, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .expired)
        XCTAssertEqual(r.remaining, 0)
    }

    func testClockBeforeFirstLaunchCannotExtendTrial() {
        // If `now` precedes `firstLaunch` (clock skew / rollback that slipped past
        // the high-water-mark clamp, or a cleared high-water mark), elapsed days go
        // negative. The trial must still be treated as day 0 (full duration), never
        // reporting MORE than `durationDays` remaining, which would extend the trial.
        let start = date(2026, 6, 1)
        let now = date(2026, 5, 1) // a month "before" the trial began
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: now, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .trial)
        XCTAssertEqual(r.remaining, 30, "remaining must be clamped to the full duration, not exceed it")
    }

    func testSameInstantIsNotNegative() {
        // Sub-day precision: `now` a few hours before `firstLaunch` still yields 0
        // whole days elapsed (not -1), so remaining stays at the full duration.
        let start = date(2026, 6, 1)
        let earlier = cal.date(byAdding: .hour, value: -5, to: start)!
        let r = LicenseLogic.trialStatus(firstLaunch: start, now: earlier, durationDays: 30, calendar: cal)
        XCTAssertEqual(r.status, .trial)
        XCTAssertEqual(r.remaining, 30)
    }

    func testProGatingAllowsProAndTrialOnly() {
        XCTAssertTrue(LicenseLogic.allowsProFeatures(.pro))
        XCTAssertTrue(LicenseLogic.allowsProFeatures(.trial))
        XCTAssertFalse(LicenseLogic.allowsProFeatures(.free))
        XCTAssertFalse(LicenseLogic.allowsProFeatures(.expired))
    }

    func testDefaultTrialDurationIsThirtyDays() {
        XCTAssertEqual(LicenseLogic.trialDurationDays, 30)
    }

    func testStatusCodableRoundTrip() throws {
        for status in [LicenseStatus.trial, .pro, .expired, .free] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(LicenseStatus.self, from: data)
            XCTAssertEqual(status, decoded)
        }
    }
}
