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
        XCTAssertEqual(Belt.belt(forGoalDays: 5000), .black)
        XCTAssertNil(Belt.black.next)
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
