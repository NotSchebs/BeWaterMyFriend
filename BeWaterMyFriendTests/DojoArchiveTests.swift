import XCTest
@testable import BeWaterMyFriend

@MainActor
final class DojoArchiveTests: XCTestCase {
    private let goal = 2000.0

    private func summaries(_ goalReached: [Date: Bool]) -> [DaySummary] {
        goalReached.map { day, reached in
            var s = DaySummary(day: day)
            s.entryCount = 1
            s.goalFluidML = reached ? 2500 : 800
            return s
        }
    }

    /// Archive + recent days must give exactly what the full recalculation gives.
    func testArchiveMatchesFullCalculationOnRandomHistories() {
        let today = date(2026, 10, 27)
        for seed in 1...40 {
            var rng = SeededRandom(state: UInt64(seed))
            var days: [Date: Bool] = [:]
            for offset in 0..<300 where Double.random(in: 0..<1, using: &rng) < 0.8 {
                let day = zurich.date(byAdding: .day, value: -offset, to: today)!
                days[day] = Double.random(in: 0..<1, using: &rng) < 0.7
            }
            let all = summaries(days)
            let full = DojoProgress.stats(days: all, goalML: goal, today: today, calendar: zurich)

            let limit = DojoArchive.archiveLimit(today: today, calendar: zurich)
            let archive = DojoArchive().advanced(through: limit, days: all.filter { $0.day <= limit },
                                                 goalML: goal, calendar: zurich)
            let fast = DojoProgress.stats(recentDays: all.filter { $0.day > limit }, archive: archive,
                                          goalML: goal, today: today, calendar: zurich)
            XCTAssertEqual(fast, full, "seed \(seed)")
        }
    }

    func testAdvancingInStepsEqualsAdvancingOnce() {
        let today = date(2026, 10, 27)
        var days: [Date: Bool] = [:]
        for offset in 0..<60 { days[zurich.date(byAdding: .day, value: -offset, to: today)!] = offset % 5 != 0 }
        let all = summaries(days)
        let once = DojoArchive().advanced(through: date(2026, 10, 20), days: all.filter { $0.day <= date(2026, 10, 20) },
                                          goalML: goal, calendar: zurich)
        let first = DojoArchive().advanced(through: date(2026, 10, 1), days: all.filter { $0.day <= date(2026, 10, 1) },
                                           goalML: goal, calendar: zurich)
        let second = first.advanced(through: date(2026, 10, 20),
                                    days: all.filter { $0.day > date(2026, 10, 1) && $0.day <= date(2026, 10, 20) },
                                    goalML: goal, calendar: zurich)
        XCTAssertEqual(once, second)
    }

    func testStreakRunningIntoTheArchiveContinues() {
        let today = date(2026, 10, 27)
        var days: [Date: Bool] = [:]
        for offset in 0..<20 { days[zurich.date(byAdding: .day, value: -offset, to: today)!] = true }
        let all = summaries(days)
        let limit = DojoArchive.archiveLimit(today: today, calendar: zurich)
        let archive = DojoArchive().advanced(through: limit, days: all.filter { $0.day <= limit }, goalML: goal, calendar: zurich)
        XCTAssertEqual(archive.trailingRun, 13)
        let stats = DojoProgress.stats(recentDays: all.filter { $0.day > limit }, archive: archive,
                                       goalML: goal, today: today, calendar: zurich)
        XCTAssertEqual(stats.currentStreak, 20)
        XCTAssertEqual(stats.goalDays, 20)
    }

    func testEmptyArchiveAndNoData() {
        let stats = DojoProgress.stats(recentDays: [], archive: DojoArchive(), goalML: goal,
                                       today: date(2026, 10, 27), calendar: zurich)
        XCTAssertEqual(stats, DojoStats())
        let archive = DojoArchive().advanced(through: date(2026, 10, 20), days: [], goalML: goal, calendar: zurich)
        XCTAssertEqual(archive.throughDay, date(2026, 10, 20))
        XCTAssertEqual(archive.goalDays, 0)
    }
}
