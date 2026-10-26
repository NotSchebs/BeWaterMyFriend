import XCTest
@testable import BeWaterMyFriend

final class CalendarGridTests: XCTestCase {
    private var monday: Calendar {
        var c = zurich
        c.firstWeekday = 2
        return c
    }

    func testOctober2026StartsOnThursday() {
        // 1 Oct 2026 is a Thursday → 3 empty cells before it (Mo, Tu, We).
        let cells = CalendarGrid.cells(forMonthContaining: date(2026, 10, 15), calendar: monday)
        XCTAssertEqual(cells.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertEqual(cells[3], date(2026, 10, 1))
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
        XCTAssertEqual(cells.count % 7, 0)
        XCTAssertEqual(cells.compactMap { $0 }.last, date(2026, 10, 31))
    }

    func testDaylightSavingDayIsStillOneCell() {
        // 25 Oct 2026 has 25 hours; every day must appear exactly once.
        let days = CalendarGrid.cells(forMonthContaining: date(2026, 10, 1), calendar: monday).compactMap { $0 }
        XCTAssertEqual(Set(days).count, 31)
        XCTAssertTrue(days.contains(date(2026, 10, 25)))
        XCTAssertTrue(days.contains(date(2026, 10, 26)))
    }

    func testFebruaryAndSundayStart() {
        var sunday = zurich
        sunday.firstWeekday = 1
        // 1 Feb 2026 is a Sunday → no padding with Sunday-first weeks.
        let cells = CalendarGrid.cells(forMonthContaining: date(2026, 2, 10), calendar: sunday)
        XCTAssertEqual(cells.first, date(2026, 2, 1))
        XCTAssertEqual(cells.compactMap { $0 }.count, 28)
        XCTAssertEqual(CalendarGrid.weekdaySymbols(calendar: monday).count, 7)
    }
}
