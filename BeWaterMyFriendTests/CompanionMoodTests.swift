import XCTest
@testable import BeWaterMyFriend

/// Moods, jitter and the drop's colour layers.
@MainActor
final class CompanionMoodTests: XCTestCase {
    private let now = date(2026, 10, 24, 15, 0)

    private func entry(_ category: DrinkCategory, ml: Double, minutesAgo: Double,
                       caffeinePer100: Double? = nil, abv: Double? = nil) -> DrinkEntry {
        var nutrients = Nutrients()
        nutrients.caffeineMg = caffeinePer100
        return DrinkEntry(timestamp: now.addingTimeInterval(-minutesAgo * 60), name: "x", category: category,
                          volumeML: ml, alcoholPercent: abv, nutrientsPer100ml: nutrients)
    }

    func testCalmWithJustWater() {
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.water, ml: 500, minutesAgo: 10)], now: now), .calm)
    }

    func testHyperNeedsEnoughCaffeine() {
        let tea = entry(.tea, ml: 250, minutesAgo: 10, caffeinePer100: 12)  // 30 mg
        XCTAssertEqual(CompanionLogic.mood(entries: [tea], now: now), .calm, "a tea isn't enough")
        let espresso = entry(.coffee, ml: 30, minutesAgo: 20, caffeinePer100: 210)  // 63 mg
        XCTAssertEqual(CompanionLogic.mood(entries: [espresso], now: now), .hyper)
        XCTAssertEqual(CompanionLogic.mood(entries: [tea, entry(.tea, ml: 250, minutesAgo: 60, caffeinePer100: 12)], now: now),
                       .hyper, "two teas add up to 60 mg")
    }

    func testWaterDoesNotCancelCaffeine() {
        let espresso = entry(.coffee, ml: 30, minutesAgo: 30, caffeinePer100: 210)
        let water = entry(.water, ml: 500, minutesAgo: 5)
        XCTAssertEqual(CompanionLogic.mood(entries: [espresso, water], now: now), .hyper)
    }

    func testCaffeineWearsOffAfterThreeHoursWithEndTime() throws {
        let espresso = entry(.coffee, ml: 30, minutesAgo: 120, caffeinePer100: 210)
        let state = CompanionLogic.moodState(entries: [espresso], now: now)
        XCTAssertEqual(state.mood, .hyper)
        XCTAssertEqual(try XCTUnwrap(state.until).timeIntervalSince(now), 3600, accuracy: 1)
        XCTAssertEqual(state.reason, "63 mg caffeine in the last 3 h")
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.coffee, ml: 30, minutesAgo: 181, caffeinePer100: 210)], now: now), .calm)
    }

    func testTipsyFromOneStandardDrinkWithinTwoHours() {
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.beer, ml: 330, minutesAgo: 30, abv: 5)], now: now), .tipsy)
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.beer, ml: 330, minutesAgo: 130, abv: 5)], now: now), .calm)
        let small = entry(.beer, ml: 200, minutesAgo: 30, abv: 5)  // 0.8 std
        XCTAssertEqual(CompanionLogic.mood(entries: [small], now: now), .calm)
    }

    func testAlcoholBeatsCaffeineWhateverCameLast() {
        let beer = entry(.beer, ml: 330, minutesAgo: 30, abv: 5)
        let coffee = entry(.coffee, ml: 250, minutesAgo: 10, caffeinePer100: 40)
        XCTAssertEqual(CompanionLogic.mood(entries: [beer, coffee], now: now), .tipsy)
    }

    func testDrunkFromThreeStandardDrinksInThreeHours() {
        let beers = (0..<3).map { entry(.beer, ml: 330, minutesAgo: 150 - Double($0) * 30, abv: 5) }
        XCTAssertEqual(CompanionLogic.mood(entries: beers + [entry(.water, ml: 250, minutesAgo: 5)], now: now), .drunk)
        let old = (0..<3).map { entry(.beer, ml: 330, minutesAgo: 240 + Double($0) * 10, abv: 5) }
        XCTAssertEqual(CompanionLogic.mood(entries: old, now: now), .calm)
    }

    func testEndTimeWithSeveralDrinks() throws {
        // 2 × 40 mg: drops below 60 mg when the first leaves the 3 h window.
        let items = [(now.addingTimeInterval(-7200), 40.0), (now.addingTimeInterval(-600), 40.0)]
        let end = try XCTUnwrap(CompanionLogic.endTime(items, threshold: 60, window: 3 * 3600))
        XCTAssertEqual(end.timeIntervalSince(now), 3600, accuracy: 1)
    }

    func testJitterFiveSecondsTwiceAMinute() {
        let minute = Date(timeIntervalSinceReferenceDate: 600)  // exactly on a minute
        XCTAssertTrue(CompanionLogic.isJitterBurst(at: minute))
        XCTAssertTrue(CompanionLogic.isJitterBurst(at: minute.addingTimeInterval(4.9)))
        XCTAssertFalse(CompanionLogic.isJitterBurst(at: minute.addingTimeInterval(5)))
        XCTAssertTrue(CompanionLogic.isJitterBurst(at: minute.addingTimeInterval(30)))
        XCTAssertFalse(CompanionLogic.isJitterBurst(at: minute.addingTimeInterval(35)))
        XCTAssertFalse(CompanionLogic.isJitterBurst(at: minute.addingTimeInterval(59)))
    }

    func testSameColoursAreGroupedEvenWhenNotNextToEachOther() {
        let entries = [
            entry(.water, ml: 500, minutesAgo: 300),
            entry(.coffee, ml: 250, minutesAgo: 200),
            entry(.sparklingWater, ml: 300, minutesAgo: 100),
            entry(.coffee, ml: 250, minutesAgo: 50),
        ]
        let totals = CompanionLogic.tintTotals(entries: entries)
        XCTAssertEqual(totals, [TintTotal(tint: .water, ml: 800), TintTotal(tint: .coffee, ml: 500)])
        let layers = CompanionLogic.fillLayers(entries: entries, goalML: 2000)
        XCTAssertEqual(layers.map(\.tint), [.water, .coffee])
        XCTAssertEqual(layers[0].fraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(layers[1].fraction, 0.25, accuracy: 0.0001)
    }

    func testLegendUsesGoalMillilitres() {
        // A 330 ml beer counts 313.5 ml (95 %); the legend shows what counts.
        let totals = CompanionLogic.tintTotals(entries: [entry(.beer, ml: 330, minutesAgo: 10, abv: 5)])
        XCTAssertEqual(totals.first?.ml ?? 0, 313.5, accuracy: 0.0001)
    }

    func testStrongAndChargedFromPowders() {
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.proteinShake, ml: 300, minutesAgo: 30)], now: now), .strong)
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.electrolytes, ml: 500, minutesAgo: 30)], now: now), .charged)
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.proteinShake, ml: 300, minutesAgo: 61)], now: now), .calm)
    }

    func testFutureEntriesDontCount() {
        let later = entry(.beer, ml: 500, minutesAgo: -60, abv: 5)
        XCTAssertEqual(CompanionLogic.mood(entries: [later], now: now), .calm)
    }

    func testFillLayersInOrderAndMerged() {
        let entries = [
            entry(.water, ml: 500, minutesAgo: 300),
            entry(.sparklingWater, ml: 300, minutesAgo: 240),  // same colour as water → merged
            entry(.coffee, ml: 250, minutesAgo: 120),
        ]
        let layers = CompanionLogic.fillLayers(entries: entries.shuffled(), goalML: 2000)
        XCTAssertEqual(layers.map(\.tint), [.water, .coffee])
        XCTAssertEqual(layers[0].fraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(layers[1].fraction, 0.125, accuracy: 0.0001)
    }

    func testPastTheGoalEveryDrinkStaysVisible() {
        let entries = [
            entry(.water, ml: 1500, minutesAgo: 300),
            entry(.coffee, ml: 500, minutesAgo: 120),
            entry(.beer, ml: 1000, minutesAgo: 60, abv: 5),  // 950 ml counted, after the goal was reached
        ]
        let layers = CompanionLogic.fillLayers(entries: entries, goalML: 2000)
        XCTAssertEqual(layers.map(\.tint), [.water, .coffee, .beer])
        XCTAssertEqual(layers.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.0001)
        XCTAssertEqual(layers[2].fraction, 950.0 / 2950, accuracy: 0.0001)  // proportional share
    }
}
