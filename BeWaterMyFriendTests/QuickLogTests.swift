import XCTest
@testable import BeWaterMyFriend

@MainActor
final class QuickLogTests: XCTestCase {
    private func preset(_ name: String, order: Int, favourite: Bool = false, shown: Bool = true) -> DrinkPreset {
        let p = DrinkPreset(name: name, category: .water, volumeML: 250, isFavourite: favourite, sortOrder: order)
        p.isInQuickLog = shown
        return p
    }

    func testQuickLogShowsAtMostTwelveFavouritesFirst() {
        var presets = (0..<15).map { preset("Drink \($0)", order: $0) }
        presets.append(preset("Fav", order: 20, favourite: true))
        presets.append(preset("Hidden", order: 21, shown: false))
        let visible = QuickLogRules.visible(presets)
        XCTAssertEqual(visible.count, 12)
        XCTAssertEqual(visible.first?.name, "Fav")
        XCTAssertFalse(visible.contains { $0.name == "Hidden" })
        XCTAssertTrue(QuickLogRules.isFull(presets))
    }

    func testOlderPresetsWithoutTheFlagAreShown() {
        let p = DrinkPreset(name: "Old", category: .water, volumeML: 250)
        XCTAssertNil(p.inQuickLog)
        XCTAssertTrue(p.isInQuickLog)
    }

    func testFindsExistingPresetByBarcodeOrNameAndType() {
        let cola = DrinkPreset(name: "Coca-Cola", category: .softDrink, volumeML: 330, barcode: "5449000000996")
        let presets = [cola]
        XCTAssertTrue(QuickLogRules.existingPreset(barcode: "5449000000996", name: "x", category: .other, in: presets) === cola)
        XCTAssertTrue(QuickLogRules.existingPreset(barcode: nil, name: " coca-cola ", category: .softDrink, in: presets) === cola)
        XCTAssertNil(QuickLogRules.existingPreset(barcode: nil, name: "Coca-Cola", category: .water, in: presets))
    }

    func testSearchFindsPastDrinksOncePerNameAndAmount() {
        let entries = [
            DrinkEntry(timestamp: date(2026, 10, 25, 9), name: "Matcha Latte", category: .tea, volumeML: 300),
            DrinkEntry(timestamp: date(2026, 10, 24, 9), name: "Matcha latte", category: .tea, volumeML: 300),
            DrinkEntry(timestamp: date(2026, 10, 23, 9), name: "Mate", category: .tea, volumeML: 500),
        ]
        let results = DrinkSearch.results(query: "mat", presets: [], entries: entries)
        XCTAssertEqual(results.map(\.draft.name), ["Matcha Latte", "Mate"])
        XCTAssertTrue(DrinkSearch.results(query: "cola", presets: [], entries: entries).isEmpty)
    }
}
