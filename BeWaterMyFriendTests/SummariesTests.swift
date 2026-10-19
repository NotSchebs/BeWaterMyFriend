import XCTest
@testable import BeWaterMyFriend

@MainActor
final class SummariesTests: XCTestCase {
    private let lateBoundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)

    private func water(_ ml: Double, at time: Date) -> DrinkEntry {
        DrinkEntry(timestamp: time, name: "Water", category: .water, volumeML: ml)
    }

    private func espresso(at time: Date) -> DrinkEntry {
        var nutrients = Nutrients()
        nutrients.caffeineMg = 210
        return DrinkEntry(timestamp: time, name: "Espresso", category: .coffee, volumeML: 30, nutrientsPer100ml: nutrients)
    }

    private func beer(at time: Date) -> DrinkEntry {
        DrinkEntry(timestamp: time, name: "Beer", category: .beer, volumeML: 330, alcoholPercent: 5)
    }

    func testGroupsEntriesByLogicalDay() {
        let entries = [
            water(250, at: date(2026, 10, 16, 22, 0)),
            water(300, at: date(2026, 10, 17, 1, 0)),  // before 03:00 → still 16 Oct
            water(500, at: date(2026, 10, 17, 9, 0)),
        ]
        let days = Summaries.daily(entries: entries, boundary: lateBoundary)
        XCTAssertEqual(days.map(\.day), [date(2026, 10, 17), date(2026, 10, 16)])
        XCTAssertEqual(days[0].goalFluidML, 500)
        XCTAssertEqual(days[1].goalFluidML, 550)
        XCTAssertEqual(days[1].entryCount, 2)
    }

    func testAlcoholCountsInTotalButNotTowardGoal() {
        let day = Summaries.daily(entries: [water(500, at: date(2026, 10, 16, 12)), beer(at: date(2026, 10, 16, 20))],
                                  boundary: lateBoundary)[0]
        XCTAssertEqual(day.goalFluidML, 500)
        XCTAssertEqual(day.totalFluidML, 830)
        XCTAssertEqual(day.alcoholGrams, 13.0185, accuracy: 0.0001)
    }

    func testCaffeineIsSummedFromPer100mlValues() {
        let day = Summaries.daily(entries: [espresso(at: date(2026, 10, 16, 8)), espresso(at: date(2026, 10, 16, 14))],
                                  boundary: lateBoundary)[0]
        XCTAssertEqual(day.caffeineMg, 126, accuracy: 0.0001)  // 2 × 63 mg
        XCTAssertEqual(day.goalFluidML, 60)  // coffee counts toward the goal
    }

    func testUnknownNutrientsAreNotTreatedAsZero() {
        var withSodium = Nutrients()
        withSodium.sodiumMg = 10
        let entries = [
            DrinkEntry(timestamp: date(2026, 10, 16, 9), name: "Mineral water", category: .sparklingWater,
                       volumeML: 500, nutrientsPer100ml: withSodium),
            water(250, at: date(2026, 10, 16, 10)),  // sodium unknown
        ]
        let day = Summaries.daily(entries: entries, boundary: lateBoundary)[0]
        XCTAssertEqual(day.nutrientTotals[.sodium], 50)
        XCTAssertNil(day.nutrientTotals[.magnesium], "no drink had magnesium data")
    }

    func testDayWithoutEntriesIsAbsentNotZero() {
        let entries = [water(250, at: date(2026, 10, 14, 12)), water(250, at: date(2026, 10, 16, 12))]
        let days = Summaries.daily(entries: entries, boundary: lateBoundary)
        XCTAssertFalse(days.contains { $0.day == date(2026, 10, 15) })
    }

    func testSummaryForEmptyDayIsZero() {
        let summary = Summaries.summary(forLogicalDay: date(2026, 10, 15), entries: [], boundary: lateBoundary)
        XCTAssertEqual(summary.entryCount, 0)
        XCTAssertEqual(summary.goalFluidML, 0)
    }

    func testSummaryForDayUsesDayEnd() {
        let entries = [
            water(250, at: date(2026, 10, 16, 2, 0)),  // belongs to 15 Oct
            water(300, at: date(2026, 10, 16, 12, 0)),
            water(400, at: date(2026, 10, 17, 2, 30)),  // still 16 Oct
        ]
        let summary = Summaries.summary(forLogicalDay: date(2026, 10, 16), entries: entries, boundary: lateBoundary)
        XCTAssertEqual(summary.goalFluidML, 700)
    }

    func testGoalProgress() {
        var day = DaySummary(day: date(2026, 10, 16))
        day.goalFluidML = 1500
        XCTAssertEqual(day.progress(goalML: 2000), 0.75)
        XCTAssertFalse(day.goalReached(goalML: 2000))
        day.goalFluidML = 2000
        XCTAssertTrue(day.goalReached(goalML: 2000))
        XCTAssertEqual(day.progress(goalML: 0), 0)
    }

    func testMonthlySummary() {
        let entries = [
            water(2000, at: date(2026, 10, 1, 12)),
            water(1000, at: date(2026, 10, 2, 12)),
            water(500, at: date(2026, 11, 1, 2, 0)),  // before 03:00 → logical day 31 Oct
            water(800, at: date(2026, 11, 3, 12)),
        ]
        let days = Summaries.daily(entries: entries, boundary: lateBoundary)
        let months = Summaries.monthly(days: days, goalML: 2000, calendar: zurich)
        XCTAssertEqual(months.map(\.month), [date(2026, 11, 1), date(2026, 10, 1)])

        let october = months[1]
        XCTAssertEqual(october.loggedDays, 3)
        XCTAssertEqual(october.daysGoalReached, 1)
        XCTAssertEqual(october.goalFluidML, 3500)
        XCTAssertEqual(october.averageGoalFluidPerLoggedDay, 3500.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(months[0].loggedDays, 1)
    }
}
