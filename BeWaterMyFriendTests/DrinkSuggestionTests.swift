import XCTest
@testable import BeWaterMyFriend

@MainActor
final class DrinkSuggestionTests: XCTestCase {
    private let now = date(2026, 10, 29, 8, 0)

    private func log(_ name: String, day: Int, hour: Int, minute: Int = 0, ml: Double = 30,
                     category: DrinkCategory = .coffee) -> DrinkEntry {
        DrinkEntry(timestamp: date(2026, 10, day, hour, minute), name: name, category: category, volumeML: ml)
    }

    func testUsualDrinkNeedsThreeDifferentDays() {
        let twoDays = [log("Espresso", day: 27, hour: 8), log("Espresso", day: 28, hour: 7, minute: 45)]
        XCTAssertNil(DrinkSuggestion.usual(entries: twoDays, now: now, calendar: zurich))
        // Three logs on one day are still one day.
        let oneDay = (0..<3).map { log("Espresso", day: 28, hour: 8, minute: $0 * 10) }
        XCTAssertNil(DrinkSuggestion.usual(entries: oneDay, now: now, calendar: zurich))

        let three = twoDays + [log("Espresso", day: 26, hour: 9, minute: 15)]
        XCTAssertEqual(DrinkSuggestion.usual(entries: three, now: now, calendar: zurich)?.timestamp, date(2026, 10, 28, 7, 45))
    }

    func testOnlyDrinksAroundThisTimeOfDayCount() {
        // Evening beers don't count in the morning; morning coffee on 4 days wins.
        var entries = (20...26).map { log("Beer", day: $0, hour: 20, ml: 500, category: .beer) }
        entries += (24...27).map { log("Espresso", day: $0, hour: 8, minute: 30) }
        XCTAssertEqual(DrinkSuggestion.usual(entries: entries, now: now, calendar: zurich)?.name, "Espresso")
        // Same name but a different size is a different drink.
        let sizes = [log("Espresso", day: 25, hour: 8), log("Espresso", day: 26, hour: 8, ml: 60),
                     log("Espresso", day: 27, hour: 8)]
        XCTAssertNil(DrinkSuggestion.usual(entries: sizes, now: now, calendar: zurich))
    }

    func testOldDrinksAreIgnoredAndMidnightWraps() {
        // Five mornings in September are more than 30 days ago.
        let old = (1...5).map { DrinkEntry(timestamp: date(2026, 9, $0, 8), name: "Espresso", category: .coffee, volumeML: 30) }
        XCTAssertNil(DrinkSuggestion.usual(entries: old, now: now, calendar: zurich))
        // 23:30 tea is "around" 00:30.
        let tea = (25...27).map { log("Tea", day: $0, hour: 23, minute: 30, ml: 250, category: .tea) }
        XCTAssertEqual(DrinkSuggestion.usual(entries: tea, now: date(2026, 10, 29, 0, 30), calendar: zurich)?.name, "Tea")
    }
}
