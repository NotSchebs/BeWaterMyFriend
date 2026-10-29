import XCTest
@testable import BeWaterMyFriend

@MainActor
final class StatsCompanionTests: XCTestCase {
    private let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
    private let today = date(2026, 10, 26)

    private func water(_ ml: Double, on day: Int) -> DrinkEntry {
        DrinkEntry(timestamp: date(2026, 10, day, 12), name: "Water", category: .water, volumeML: ml)
    }

    private func setup(_ entries: [DrinkEntry]) -> (StatsReport, [WeekdayPoint]) {
        let report = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: today, boundary: boundary)
        return (report, StatsCalculator.weekdays(report.points, calendar: zurich))
    }

    func testWithoutATapTheDropStandsOnTheInsightSpot() throws {
        // Weekends drier than weekdays → the weekday chart, on Sunday.
        var entries = (20...23).map { water(2000, on: $0) }
        entries += [water(1200, on: 24), water(800, on: 25)]
        let (report, weekdays) = setup(entries)
        let spot = try XCTUnwrap(StatsCompanion.spot(pin: nil, report: report, weekdays: weekdays, entries: entries,
                                                     goalML: 2000, calendar: zurich, today: today, taps: 0))
        XCTAssertEqual(spot.chart, .weekday)
        XCTAssertEqual(spot.weekday, 1)
        XCTAssertTrue(spot.text.contains("weekends"), spot.text)
    }

    func testTappedBarWinsAndDescribesThatDay() throws {
        let entries = (20...25).map { water($0 == 23 ? 2500 : 1500, on: $0) }
        let (report, weekdays) = setup(entries)
        let pin = StatsCompanion.Pin(chart: .daily, day: date(2026, 10, 23))
        let spot = try XCTUnwrap(StatsCompanion.spot(pin: pin, report: report, weekdays: weekdays, entries: entries,
                                                     goalML: 2000, calendar: zurich, today: today, taps: 0))
        XCTAssertEqual(spot.day, date(2026, 10, 23))
        XCTAssertTrue(spot.text.contains("Goal reached"), spot.text)
        XCTAssertEqual(spot.progress, 1.25, accuracy: 0.001)

        // A day without drinks still gets a drop ("nothing logged"); a day outside the chart doesn't.
        let empty = try XCTUnwrap(StatsCompanion.spot(pin: .init(chart: .daily, day: date(2026, 10, 26)), report: report,
                                                      weekdays: weekdays, entries: entries, goalML: 2000,
                                                      calendar: zurich, today: today, taps: 0))
        XCTAssertTrue(empty.text.contains("Nothing logged"), empty.text)
        XCTAssertNil(StatsCompanion.spot(pin: .init(chart: .daily, day: date(2026, 9, 1)), report: report,
                                         weekdays: weekdays, entries: entries, goalML: 2000,
                                         calendar: zurich, today: today, taps: 0))
    }

    func testNoDropWithTooLittleData() {
        let entries = [water(2000, on: 26)]
        let (report, weekdays) = setup(entries)
        XCTAssertNil(StatsCompanion.spot(pin: nil, report: report, weekdays: weekdays, entries: entries,
                                         goalML: 2000, calendar: zurich, today: today, taps: 0))
    }

    func testDonutSliceFromTapPosition() {
        // Half water, half coffee: water from 12 to 6 o'clock (right), coffee on the left.
        let totals = [TintTotal(tint: .water, ml: 500), TintTotal(tint: .coffee, ml: 500)]
        let size = CGSize(width: 120, height: 120)
        XCTAssertEqual(StatsCompanion.donutSlice(at: CGPoint(x: 110, y: 60), in: size, totals: totals), .water)
        XCTAssertEqual(StatsCompanion.donutSlice(at: CGPoint(x: 10, y: 60), in: size, totals: totals), .coffee)
        XCTAssertNil(StatsCompanion.donutSlice(at: CGPoint(x: 60, y: 60), in: size, totals: totals))  // the hole
        XCTAssertNil(StatsCompanion.donutSlice(at: CGPoint(x: 119, y: 1), in: size, totals: totals))   // outside the ring
        XCTAssertNil(StatsCompanion.donutSlice(at: CGPoint(x: 110, y: 60), in: size, totals: []))
    }
}
