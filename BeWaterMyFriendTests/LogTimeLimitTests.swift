import XCTest
@testable import BeWaterMyFriend

final class LogTimeLimitTests: XCTestCase {
    func testDrinksCanGoBackTwoDaysNotMore() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        let now = date(2026, 10, 26, 15, 0)
        XCTAssertEqual(LogTimeLimit.earliest(now: now, boundary: boundary), date(2026, 10, 24, 0, 0))
        let range = LogTimeLimit.range(now: now, boundary: boundary)
        XCTAssertTrue(range.contains(date(2026, 10, 24, 8, 0)))
        XCTAssertFalse(range.contains(date(2026, 10, 23, 23, 0)))
        XCTAssertFalse(range.contains(date(2026, 10, 26, 16, 0)), "no future drinks")
    }

    func testCustomDayEndIsRespected() {
        let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)
        // At 01:00 on 26 Oct the logical day is still 25 Oct → earliest is 23 Oct 03:00.
        XCTAssertEqual(LogTimeLimit.earliest(now: date(2026, 10, 26, 1, 0), boundary: boundary), date(2026, 10, 23, 3, 0))
    }

    func testOlderEntryKeepsItsOwnTimeAsLowerBound() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        let old = date(2026, 10, 10, 12, 0)
        let range = LogTimeLimit.range(now: date(2026, 10, 26, 15, 0), boundary: boundary, existing: old)
        XCTAssertEqual(range.lowerBound, old)
    }
}
