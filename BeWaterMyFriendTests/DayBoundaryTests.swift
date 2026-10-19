import XCTest
@testable import BeWaterMyFriend

final class DayBoundaryTests: XCTestCase {
    func testMidnightDayEnd() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 10, 16, 23, 59)), date(2026, 10, 16))
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 10, 17, 0, 0)), date(2026, 10, 17))
    }

    func testDrinkAfterMidnightCountsForPreviousDayWithLateDayEnd() {
        let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 10, 17, 1, 0)), date(2026, 10, 16))
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 10, 17, 2, 59)), date(2026, 10, 16))
    }

    func testDrinkExactlyAtDayEndBelongsToNewDay() {
        let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 10, 17, 3, 0)), date(2026, 10, 17))
    }

    func testIntervalWithLateDayEnd() {
        let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)
        let interval = boundary.interval(forLogicalDay: date(2026, 10, 16))
        XCTAssertEqual(interval.start, date(2026, 10, 16, 3, 0))
        XCTAssertEqual(interval.end, date(2026, 10, 17, 3, 0))
        XCTAssertEqual(interval.duration, 24 * 3600)
    }

    func testIntervalAcceptsAnyTimeOnTheDay() {
        let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)
        XCTAssertEqual(
            boundary.interval(forLogicalDay: date(2026, 10, 16, 18, 30)),
            boundary.interval(forLogicalDay: date(2026, 10, 16))
        )
    }

    // MARK: Daylight saving time

    func testFallBackDayHas25Hours() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        XCTAssertEqual(boundary.interval(forLogicalDay: date(2026, 10, 25)).duration, 25 * 3600)
    }

    func testSpringForwardDayHas23Hours() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        XCTAssertEqual(boundary.interval(forLogicalDay: date(2026, 3, 29)).duration, 23 * 3600)
    }

    func testDayEndInsideSpringForwardGap() {
        // 02:30 doesn't exist on 29 Mar 2026 (clocks jump 02:00 → 03:00).
        let boundary = DayBoundary(dayEndMinutes: 2 * 60 + 30, calendar: zurich)
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 3, 29, 1, 30)), date(2026, 3, 28))
        XCTAssertEqual(boundary.logicalDay(for: date(2026, 3, 29, 4, 0)), date(2026, 3, 29))
        let start = boundary.interval(forLogicalDay: date(2026, 3, 29)).start
        XCTAssertGreaterThanOrEqual(start, date(2026, 3, 29, 3, 0))
        XCTAssertLessThanOrEqual(start, date(2026, 3, 29, 3, 30))
    }

    func testDayEndInsideRepeatedFallBackHourUsesFirstOccurrence() {
        // 02:30 happens twice on 25 Oct 2026 (clocks go 03:00 → 02:00).
        let boundary = DayBoundary(dayEndMinutes: 2 * 60 + 30, calendar: zurich)
        let start = boundary.interval(forLogicalDay: date(2026, 10, 25)).start
        // First 02:30 is still summer time (UTC+2) = 00:30 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(start, utc.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 30)))
    }

    /// Every logical day must start exactly where the previous one ended (no gaps,
    /// no overlaps), all year round, for several day-end settings.
    func testDaysAreContiguousAllYear() {
        for minutes in [0, 60, 2 * 60 + 30, 3 * 60, 5 * 60 + 45] {
            let boundary = DayBoundary(dayEndMinutes: minutes, calendar: zurich)
            var day = date(2026, 1, 1)
            for _ in 0..<366 {
                let next = zurich.date(byAdding: .day, value: 1, to: day)!
                let interval = boundary.interval(forLogicalDay: day)
                XCTAssertEqual(interval.end, boundary.interval(forLogicalDay: next).start, "gap after \(day), end \(minutes)")
                XCTAssertEqual(boundary.logicalDay(for: interval.start), day, "start of \(day), end \(minutes)")
                XCTAssertEqual(boundary.logicalDay(for: interval.end.addingTimeInterval(-1)), day, "end of \(day), end \(minutes)")
                day = next
            }
        }
    }
}
