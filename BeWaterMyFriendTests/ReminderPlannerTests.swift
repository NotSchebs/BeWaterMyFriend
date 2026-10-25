import XCTest
@testable import BeWaterMyFriend

/// Deterministic random numbers for tests (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class ReminderPlannerTests: XCTestCase {
    private let day = date(2026, 10, 26)

    private func minutes(_ d: Date) -> Int {
        let c = zurich.dateComponents([.hour, .minute], from: d)
        return c.hour! * 60 + c.minute!
    }

    func testOneReminderPerIntervalInsideTheWindow() {
        let settings = ReminderSettings(startMinutes: 9 * 60, endMinutes: 18 * 60, intervalMinutes: 60)
        for seed in 1...50 {
            var rng = SeededRandom(state: UInt64(seed))
            let times = ReminderPlanner.times(on: day, settings: settings, calendar: zurich, using: &rng)
            XCTAssertTrue((8...9).contains(times.count), "seed \(seed): \(times.count) reminders")
            XCTAssertTrue(times.allSatisfy { (540..<1080).contains(minutes($0)) }, "seed \(seed): outside window")
        }
    }

    func testRemindersAreNeverTooCloseTogether() {
        let settings = ReminderSettings(startMinutes: 9 * 60, endMinutes: 18 * 60, intervalMinutes: 90)
        for seed in 1...50 {
            var rng = SeededRandom(state: UInt64(seed))
            let times = ReminderPlanner.times(on: day, settings: settings, calendar: zurich, using: &rng)
            for (a, b) in zip(times, times.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 30 * 60 - 60, "seed \(seed)")  // ≥ a third of 90 min
            }
        }
    }

    func testTimesAreRandomNotFixed() {
        let settings = ReminderSettings()
        var a = SeededRandom(state: 1), b = SeededRandom(state: 2)
        XCTAssertNotEqual(ReminderPlanner.times(on: day, settings: settings, calendar: zurich, using: &a),
                          ReminderPlanner.times(on: day, settings: settings, calendar: zurich, using: &b))
    }

    func testEmptyOrInvertedWindowGivesNoReminders() {
        var rng = SeededRandom(state: 1)
        let inverted = ReminderSettings(startMinutes: 18 * 60, endMinutes: 9 * 60)
        XCTAssertTrue(ReminderPlanner.times(on: day, settings: inverted, calendar: zurich, using: &rng).isEmpty)
    }

    func testExpectedPaceIsLinearOverTheWindow() {
        let settings = ReminderSettings(startMinutes: 9 * 60, endMinutes: 17 * 60)
        XCTAssertEqual(ReminderPlanner.expectedFraction(at: date(2026, 10, 26, 8, 0), settings: settings, calendar: zurich), 0)
        XCTAssertEqual(ReminderPlanner.expectedFraction(at: date(2026, 10, 26, 13, 0), settings: settings, calendar: zurich), 0.5)
        XCTAssertEqual(ReminderPlanner.expectedFraction(at: date(2026, 10, 26, 20, 0), settings: settings, calendar: zurich), 1)
    }

    func testSkipsPastRemindersAndOnesTheUserIsOnTrackFor() {
        let settings = ReminderSettings(startMinutes: 9 * 60, endMinutes: 17 * 60, intervalMinutes: 60, skipWhenOnTrack: true)
        let times = [10, 12, 14, 16].map { date(2026, 10, 26, $0, 0) }
        let now = date(2026, 10, 26, 11, 0)
        // 50 % drunk: on track until 13:00 → 12:00 skipped, 10:00 is past.
        XCTAssertEqual(ReminderPlanner.todaysTimes(times, now: now, progress: 0.5, settings: settings, calendar: zurich),
                       [date(2026, 10, 26, 14, 0), date(2026, 10, 26, 16, 0)])
        var always = settings
        always.skipWhenOnTrack = false
        XCTAssertEqual(ReminderPlanner.todaysTimes(times, now: now, progress: 0.5, settings: always, calendar: zurich).count, 3)
    }
}
