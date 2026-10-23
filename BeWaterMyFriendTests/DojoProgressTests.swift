import XCTest
@testable import BeWaterMyFriend

@MainActor
final class DojoProgressTests: XCTestCase {
    private func day(_ d: Int, ml: Double, month: Int = 10) -> DaySummary {
        var summary = DaySummary(day: date(2026, month, d))
        summary.goalFluidML = ml
        summary.entryCount = 1
        return summary
    }

    func testBeltThresholds() {
        XCTAssertEqual(Belt.belt(forGoalDays: 0), .white)
        XCTAssertEqual(Belt.belt(forGoalDays: 2), .white)
        XCTAssertEqual(Belt.belt(forGoalDays: 3), .yellow)
        XCTAssertEqual(Belt.belt(forGoalDays: 29), .green)
        XCTAssertEqual(Belt.belt(forGoalDays: 100), .black)
        XCTAssertEqual(Belt.belt(forGoalDays: 149), .black)
        XCTAssertEqual(Belt.belt(forGoalDays: 150), .dan1)
        XCTAssertEqual(Belt.belt(forGoalDays: 365), .dan4)
        XCTAssertEqual(Belt.belt(forGoalDays: 5000), .dan10)
        XCTAssertEqual(Belt.black.next, .dan1)
        XCTAssertNil(Belt.dan10.next)
    }

    func testDanNames() {
        XCTAssertNil(Belt.black.danLevel)
        XCTAssertEqual(Belt.dan1.danLevel, 1)
        XCTAssertEqual(Belt.dan10.danLevel, 10)
        XCTAssertEqual(Belt.dan1.name, "1st Dan")
        XCTAssertEqual(Belt.dan2.name, "2nd Dan")
        XCTAssertEqual(Belt.dan3.name, "3rd Dan")
        XCTAssertEqual(Belt.dan10.name, "10th Dan")
        XCTAssertEqual(Belt.dan10.japaneseName, "Jūdan")
        XCTAssertNil(Belt.brown.japaneseName)
    }

    func testPrestigeRestartsRanksButKeepsHistory() {
        // 1,000 goal days → 10th Dan, prestige offered.
        XCTAssertEqual(Belt.belt(forGoalDays: DojoProgress.rankGoalDays(bestTotal: 1000, currentTotal: 1000, prestigeBase: 0)), .dan10)
        XCTAssertTrue(DojoProgress.canPrestige(.dan10))
        XCTAssertFalse(DojoProgress.canPrestige(.dan9))
        // After prestige at 1,000: back to white belt, ranks count from there.
        XCTAssertEqual(DojoProgress.rankGoalDays(bestTotal: 1000, currentTotal: 1000, prestigeBase: 1000), 0)
        XCTAssertEqual(Belt.belt(forGoalDays: DojoProgress.rankGoalDays(bestTotal: 1003, currentTotal: 1003, prestigeBase: 1000)), .yellow)
        // Never negative, and the best total still protects against deleted entries.
        XCTAssertEqual(DojoProgress.rankGoalDays(bestTotal: 1010, currentTotal: 990, prestigeBase: 1000), 10)
        XCTAssertEqual(DojoProgress.rankGoalDays(bestTotal: 0, currentTotal: 0, prestigeBase: 1000), 0)
    }

    func testBeltRequirementsIncrease() {
        let required = Belt.allCases.map(\.requiredGoalDays)
        XCTAssertEqual(required, required.sorted())
        XCTAssertEqual(Set(required).count, required.count)
    }

    func testCountsOnlyGoalDays() {
        let days = [day(20, ml: 2000), day(21, ml: 1500), day(22, ml: 2500)]
        let stats = DojoProgress.stats(days: days, goalML: 2000, today: date(2026, 10, 22), calendar: zurich)
        XCTAssertEqual(stats.goalDays, 2)
    }

    func testCurrentStreakIncludesToday() {
        let days = [day(20, ml: 2000), day(21, ml: 2000), day(22, ml: 2000)]
        let stats = DojoProgress.stats(days: days, goalML: 2000, today: date(2026, 10, 22), calendar: zurich)
        XCTAssertEqual(stats.currentStreak, 3)
    }

    func testTodayNotReachedYetDoesNotBreakStreak() {
        let days = [day(20, ml: 2000), day(21, ml: 2000), day(22, ml: 500)]
        let stats = DojoProgress.stats(days: days, goalML: 2000, today: date(2026, 10, 22), calendar: zurich)
        XCTAssertEqual(stats.currentStreak, 2)
    }

    func testMissedDayEndsStreak() {
        let days = [day(18, ml: 2000), day(19, ml: 2000), day(21, ml: 2000)]
        let stats = DojoProgress.stats(days: days, goalML: 2000, today: date(2026, 10, 22), calendar: zurich)
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.bestStreak, 2)
    }

    func testStreakAcrossMonthAndDaylightSavingChange() {
        // 25 Oct 2026 has 25 hours; 31 Oct → 1 Nov crosses a month.
        let days = (24...31).map { day($0, ml: 2000) } + [day(1, ml: 2000, month: 11)]
        let stats = DojoProgress.stats(days: days, goalML: 2000, today: date(2026, 11, 1), calendar: zurich)
        XCTAssertEqual(stats.currentStreak, 9)
        XCTAssertEqual(stats.bestStreak, 9)
    }

    func testCompanionScaleGrowsWithProgressAndCaps() {
        XCTAssertEqual(DojoProgress.companionScale(progress: 0), 0.8)
        XCTAssertEqual(DojoProgress.companionScale(progress: 0.5), 0.9, accuracy: 0.0001)
        XCTAssertEqual(DojoProgress.companionScale(progress: 3), 1)
    }
}
