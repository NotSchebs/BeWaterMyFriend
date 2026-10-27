import XCTest
@testable import BeWaterMyFriend

@MainActor
final class CompanionCaptionTests: XCTestCase {
    private let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)

    private func water(_ ml: Double, on day: Int, hour: Int = 12) -> DrinkEntry {
        DrinkEntry(timestamp: date(2026, 10, day, hour), name: "Water", category: .water, volumeML: ml)
    }

    func testDayMoodAndCaption() {
        var day = DaySummary(day: date(2026, 10, 24))
        day.goalFluidML = 2500
        XCTAssertEqual(CompanionLogic.dayMood(day), .calm)
        XCTAssertEqual(CompanionLogic.dayCaption(day, goalML: 2000), "Goal reached with 2'500 ml. Well trained!")
        day.goalFluidML = 1500
        day.alcoholGrams = 40  // 4 std
        XCTAssertEqual(CompanionLogic.dayMood(day), .drunk)
        XCTAssertTrue(CompanionLogic.dayCaption(day, goalML: 2000).contains("short of the goal"))
        XCTAssertTrue(CompanionLogic.dayCaption(day, goalML: 2000).contains("party day"))
    }

    func testPreviewText() {
        XCTAssertEqual(DrinkEditorView.previewText(before: .calm, after: .hyper, ml: 30), "Caffeine! This will make me hyper.")
        XCTAssertEqual(DrinkEditorView.previewText(before: .hyper, after: .hyper, ml: 30), "This adds 30 ml toward your goal.")
    }

    func testWeekendInsight() throws {
        // 20–26 Oct 2026: Tue–Fri 2,000 ml, Sat/Sun 1,000 ml.
        var entries: [DrinkEntry] = []
        for d in 20...23 { entries.append(water(2000, on: d)) }
        for d in 24...25 { entries.append(water(1000, on: d)) }
        let r = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: date(2026, 10, 26), boundary: boundary)
        let s = try XCTUnwrap(StatsInsight.sentence(report: r, entries: entries, calendar: zurich))
        XCTAssertEqual(s, "You drink 50 % less on weekends than on weekdays.")
    }

    func testNoInsightWithTooLittleData() {
        let entries = [water(2000, on: 26)]
        let r = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: date(2026, 10, 26), boundary: boundary)
        XCTAssertNil(StatsInsight.sentence(report: r, entries: entries, calendar: zurich))
    }

    func testLateCaffeineInsight() throws {
        var entries: [DrinkEntry] = []
        var n = Nutrients()
        n.caffeineMg = 40
        for d in 22...26 {
            entries.append(water(2000, on: d))
            entries.append(DrinkEntry(timestamp: date(2026, 10, d, 17), name: "Coffee", category: .coffee, volumeML: 250, nutrientsPer100ml: n))
        }
        let r = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: date(2026, 10, 26), boundary: boundary)
        let s = try XCTUnwrap(StatsInsight.sentence(report: r, entries: entries, calendar: zurich))
        XCTAssertTrue(s.contains("after 4 pm"), s)
    }
}
