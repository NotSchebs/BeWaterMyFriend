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
        // With progress: where the drink gets us, or that it reaches the goal.
        XCTAssertEqual(DrinkEditorView.previewText(before: .calm, after: .calm, ml: 250, progressBefore: 0.4, progressAfter: 0.5),
                       "+250 ml. We'd be at 50%.")
        XCTAssertEqual(DrinkEditorView.previewText(before: .calm, after: .calm, ml: 500, progressBefore: 0.9, progressAfter: 1.15),
                       "This gets us to the goal! Osu!")
        XCTAssertEqual(CompanionLogic.mood(for: .coffee), .hyper)
        XCTAssertEqual(CompanionLogic.mood(for: .wine), .tipsy)
        XCTAssertEqual(CompanionLogic.mood(for: .water), .calm)
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

    func testInsightTargets() throws {
        // Weekend insight points at the weaker weekend day in the weekday chart.
        var entries: [DrinkEntry] = []
        for d in 20...23 { entries.append(water(2000, on: d)) }
        entries.append(water(1200, on: 24))  // Saturday
        entries.append(water(800, on: 25))   // Sunday
        let r = StatsCalculator.report(entries: entries, days: 7, goalML: 2000, today: date(2026, 10, 26), boundary: boundary)
        let insight = try XCTUnwrap(StatsInsight.make(report: r, entries: entries, calendar: zurich))
        XCTAssertEqual(insight.target, .weekday(1))  // Sunday

        // Late caffeine points at the day with the most caffeine.
        var coffee = Nutrients()
        coffee.caffeineMg = 40
        var late: [DrinkEntry] = []
        for d in 22...26 {
            late.append(water(2000, on: d))
            late.append(DrinkEntry(timestamp: date(2026, 10, d, 17), name: "Coffee", category: .coffee,
                                   volumeML: d == 24 ? 500 : 250, nutrientsPer100ml: coffee))
        }
        let r2 = StatsCalculator.report(entries: late, days: 7, goalML: 2000, today: date(2026, 10, 26), boundary: boundary)
        XCTAssertEqual(StatsInsight.make(report: r2, entries: late, calendar: zurich)?.target, .caffeine(date(2026, 10, 24)))
    }

    /// Every wording, for every kind of line: the drop never talks about what's "in" it.
    func testNoLineSaysSomethingIsInTheDrop() {
        var lines: [String] = []
        for seed in 0..<8 {
            for ml in [nil, 1000.0, 2500.0] {
                lines.append(CompanionLines.statsDay(ml: ml, goalML: 2000, dayText: "Fri", seed: seed))
            }
            lines.append(CompanionLines.statsCaffeine(mg: seed.isMultiple(of: 2) ? 0 : 100, dayText: "Fri", seed: seed))
            lines.append(CompanionLines.statsAlcohol(standardDrinks: seed.isMultiple(of: 2) ? 0 : 2, dayText: "Fri", seed: seed))
            lines.append(CompanionLines.statsWeekday(ml: 1800, weekdayText: "Saturday", seed: seed))
            lines.append(CompanionLines.statsDrinkType(name: "Water", ml: 1000, share: 0.5, seed: seed))
        }
        XCTAssertGreaterThanOrEqual(Set(lines).count, 25)
        for line in lines {
            XCTAssertFalse(line.lowercased().contains("in me"), line)
        }
    }

    func testBlackBeltSpeechIsTheFullQuote() {
        XCTAssertEqual(CompanionLines.bruceLeeQuote,
                       "Empty your mind. Be formless, shapeless, like water. You put water into a cup, it becomes the cup. "
                       + "You put water into a bottle, it becomes the bottle. You put it into a teapot, it becomes the teapot. "
                       + "Now water can flow or it can crash. Be water, my friend.")
    }

    func testWordingVariants() {
        var day = DaySummary(day: date(2026, 10, 24))
        day.goalFluidML = 2500
        XCTAssertNotEqual(CompanionLogic.dayCaption(day, goalML: 2000, seed: 0), CompanionLogic.dayCaption(day, goalML: 2000, seed: 1))
        // Any seed works, also negative and large ones.
        XCTAssertEqual(CompanionLines.pick(["a", "b", "c"], seed: -1), "c")
        XCTAssertEqual(CompanionLines.pick(["a", "b", "c"], seed: 739_000), CompanionLines.pick(["a", "b", "c"], seed: 739_000 % 3))
    }

    func testReplayFollowsTheDay() {
        var coffee = Nutrients()
        coffee.caffeineMg = 40  // per 100 ml → 100 mg for 250 ml
        let entries = [
            water(500, on: 24, hour: 8),
            DrinkEntry(timestamp: date(2026, 10, 24, 9), name: "Coffee", category: .coffee, volumeML: 250, nutrientsPer100ml: coffee),
            water(500, on: 24, hour: 10),
            DrinkEntry(timestamp: date(2026, 10, 24, 20), name: "Beer", category: .beer, volumeML: 500, alcoholPercent: 5),
        ]
        let steps = CompanionLogic.replay(entries: entries.reversed(), goalML: 2000)
        XCTAssertEqual(steps.map(\.name), ["Water", "Coffee", "Water", "Beer"])
        XCTAssertEqual(steps.map(\.mood), [.calm, .hyper, .hyper, .tipsy])  // water doesn't cancel the coffee
        XCTAssertEqual(steps.map(\.moodChanged), [false, true, false, true])
        XCTAssertEqual(steps[0].progress, 0.25, accuracy: 0.001)
        XCTAssertTrue(zip(steps, steps.dropFirst()).allSatisfy { $0.progress <= $1.progress })
        XCTAssertEqual(CompanionLines.replayLine(name: "Coffee", mood: .hyper, moodChanged: true), "Coffee – now I'm hyper!")
        XCTAssertEqual(CompanionLines.replayLine(name: "Water", mood: .hyper, moodChanged: false), "Water")
    }

    func testBestDayOfMonth() {
        var a = DaySummary(day: date(2026, 10, 3)); a.goalFluidML = 2400
        var b = DaySummary(day: date(2026, 10, 9)); b.goalFluidML = 3100
        var c = DaySummary(day: date(2026, 10, 1)); c.goalFluidML = 3100  // same amount, earlier: wins
        XCTAssertEqual(CompanionLogic.bestDay(in: [a, b, c])?.day, date(2026, 10, 1))
        XCTAssertNil(CompanionLogic.bestDay(in: []))
        XCTAssertNil(CompanionLogic.bestDay(in: [DaySummary(day: date(2026, 10, 2))]))
    }
}
