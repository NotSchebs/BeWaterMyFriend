import XCTest
@testable import BeWaterMyFriend

@MainActor
final class StatsCalculatorTests: XCTestCase {
    private let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
    private let today = date(2026, 10, 26)

    private func water(_ ml: Double, on day: Int, month: Int = 10) -> DrinkEntry {
        DrinkEntry(timestamp: date(2026, month, day, 12), name: "Water", category: .water, volumeML: ml)
    }

    func testWeekReportSkipsDaysWithoutData() {
        let entries = [water(2000, on: 26), water(1000, on: 25), water(3000, on: 22)]
        let r = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: today, boundary: boundary)
        XCTAssertEqual(r.points.count, 7)
        XCTAssertEqual(r.points.first?.day, date(2026, 10, 20))
        XCTAssertEqual(r.points.last?.day, today)
        XCTAssertEqual(r.loggedDays, 3)
        XCTAssertEqual(r.goalDays, 2)
        XCTAssertEqual(try XCTUnwrap(r.averageML), 2000, accuracy: 0.001)
        XCTAssertNil(r.points[3].ml, "23 Oct: no data, not zero")
        XCTAssertEqual(r.bestDay?.day, date(2026, 10, 22))
    }

    func testTrendComparesWithThePeriodBefore() throws {
        let entries = [water(1000, on: 15), water(1000, on: 16), water(1500, on: 24), water(1500, on: 25)]
        let r = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: today, boundary: boundary)
        XCTAssertEqual(try XCTUnwrap(r.averageChangePercent), 50, accuracy: 0.001)
    }

    func testNoTrendWithoutEarlierData() {
        let r = StatsCalculator.report(entries: [water(1000, on: 26)], days: 7, goalML: 2000, today: today, boundary: boundary)
        XCTAssertNil(r.averageChangePercent)
    }

    func testWeeklyAveragesAndWeekdays() throws {
        var monday = zurich
        monday.firstWeekday = 2
        let b = DayBoundary(dayEndMinutes: 0, calendar: monday)
        let entries = [water(2000, on: 19), water(1000, on: 20), water(3000, on: 26)]
        let weeks = StatsCalculator.weeks(entries: entries, weeks: 2, goalML: 2000, today: today, boundary: b)
        XCTAssertEqual(weeks.map(\.weekStart), [date(2026, 10, 19), date(2026, 10, 26)])
        XCTAssertEqual(try XCTUnwrap(weeks[0].averageML), 1500, accuracy: 0.001)
        XCTAssertEqual(weeks[0].goalDays, 1)
        XCTAssertEqual(weeks[1].loggedDays, 1)

        let r = StatsCalculator.report(entries: entries, days: 14, goalML: 2000, today: today, boundary: b)
        let wd = StatsCalculator.weekdays(r.points, calendar: monday)
        XCTAssertEqual(wd.first?.weekday, 2, "Monday first")
        XCTAssertEqual(try XCTUnwrap(wd.first?.averageML), 2500, accuracy: 0.001)  // 19th and 26th are Mondays
    }
}
