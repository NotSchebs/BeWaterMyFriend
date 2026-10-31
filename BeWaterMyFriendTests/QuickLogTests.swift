import XCTest
@testable import BeWaterMyFriend

@MainActor
final class QuickLogTests: XCTestCase {
    private func preset(_ name: String, order: Int, shown: Bool = true) -> DrinkPreset {
        let p = DrinkPreset(name: name, category: .water, volumeML: 250, sortOrder: order)
        p.isInQuickLog = shown
        return p
    }

    func testQuickLogShowsAtMostTwelveInTheUsersOrder() {
        var presets = (0..<15).map { preset("Drink \($0)", order: $0) }
        presets.append(preset("Hidden", order: -1, shown: false))
        let visible = QuickLogRules.visible(presets)
        XCTAssertEqual(visible.count, 12)
        XCTAssertEqual(visible.first?.name, "Drink 0")
        XCTAssertFalse(visible.contains { $0.name == "Hidden" })
        XCTAssertTrue(QuickLogRules.isFull(presets))
    }

    func testDraggedTileTakesTheSlotAndOthersShift() {
        let order = ["A", "B", "C", "D"]
        XCTAssertEqual(QuickLogRules.moved("A", toSlot: 2, in: order), ["B", "C", "A", "D"], "forward")
        XCTAssertEqual(QuickLogRules.moved("D", toSlot: 0, in: order), ["D", "A", "B", "C"], "backward")
        XCTAssertEqual(QuickLogRules.moved("B", toSlot: 1, in: order), order, "its own slot")
        XCTAssertEqual(QuickLogRules.moved("B", toSlot: 9, in: order), order, "no such slot")
    }

    func testSavingANewOrderKeepsHiddenDrinksInPlace() {
        let a = preset("A", order: 0), hidden = preset("Hidden", order: 1, shown: false)
        let b = preset("B", order: 2), c = preset("C", order: 3)
        let all = [c, a, hidden, b]
        QuickLogRules.reorder([c, a, b], in: all)
        XCTAssertEqual(QuickLogRules.visible(all).map(\.name), ["C", "A", "B"])
        XCTAssertEqual(hidden.sortOrder, 1, "Settings keeps it where it was")

        // A star doesn't change the Quick log order.
        DrinkStars.star(b, in: all)
        XCTAssertEqual(QuickLogRules.visible(all).map(\.name), ["C", "A", "B"])
    }

    func testMatchingANewTileIsExact() {
        let coffee = DrinkPreset(name: "Coffee", category: .coffee, volumeML: 250)
        let cola = DrinkPreset(name: "Cola", category: .softDrink, volumeML: 330, barcode: "5449000000996")
        var draft = DrinkDraft()
        draft.name = " coffee "
        draft.category = .coffee
        draft.volumeML = 250
        XCTAssertTrue(QuickLogRules.matching(draft, in: [coffee, cola]) === coffee)
        draft.volumeML = 500   // a bigger coffee is its own tile
        XCTAssertNil(QuickLogRules.matching(draft, in: [coffee, cola]))
        draft.barcode = "5449000000996"
        XCTAssertTrue(QuickLogRules.matching(draft, in: [coffee, cola]) === cola)
        XCTAssertEqual(QuickLogRules.nextSortOrder([]), 0)
        coffee.sortOrder = 7
        XCTAssertEqual(QuickLogRules.nextSortOrder([coffee, cola]), 8)
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

@MainActor
final class DrinkStarsTests: XCTestCase {
    private func drinks(_ names: String...) -> [DrinkPreset] {
        names.enumerated().map { DrinkPreset(name: $1, category: .water, volumeML: 250, sortOrder: $0) }
    }

    private func stars(_ presets: [DrinkPreset]) -> [String] {
        DrinkStars.starred(presets).map { "\($0.starNumber ?? 0)\($0.name)" }
    }

    func testStarringTakesTheNextNumberUpToThree() {
        let all = drinks("A", "B", "C", "D")
        for preset in all.prefix(3) { XCTAssertTrue(DrinkStars.star(preset, in: all)) }
        XCTAssertEqual(stars(all), ["1A", "2B", "3C"])
        XCTAssertFalse(DrinkStars.star(all[3], in: all), "a fourth star is refused")
        XCTAssertNil(all[3].starNumber)
        XCTAssertTrue(DrinkStars.star(all[0], in: all), "already starred: nothing changes")
        XCTAssertEqual(stars(all), ["1A", "2B", "3C"])
    }

    func testUnstarringFreesTheNumberAndOthersMoveUp() {
        let all = drinks("A", "B", "C", "D")
        for preset in all.prefix(3) { DrinkStars.star(preset, in: all) }
        DrinkStars.unstar(all[0], in: all)
        XCTAssertEqual(stars(all), ["1B", "2C"])
        DrinkStars.star(all[3], in: all)
        XCTAssertEqual(stars(all), ["1B", "2C", "3D"])
    }

    func testChoosingANumberSwapsOrReplaces() {
        let all = drinks("A", "B", "C", "D")
        for preset in all.prefix(3) { DrinkStars.star(preset, in: all) }
        DrinkStars.assign(all[2], number: 1, in: all)
        XCTAssertEqual(stars(all), ["1C", "2B", "3A"], "swap")
        DrinkStars.assign(all[3], number: 2, in: all)
        XCTAssertEqual(stars(all), ["1C", "2D", "3A"], "replace")
        XCTAssertNil(all[1].starNumber)
        DrinkStars.assign(all[0], number: 3, in: all)
        XCTAssertEqual(stars(all), ["1C", "2D", "3A"], "its own number: nothing changes")
    }

    func testDeletedStarLeavesNoGap() {
        let all = drinks("A", "B", "C")
        for preset in all { DrinkStars.star(preset, in: all) }
        DrinkStars.compact([all[1], all[2]])   // A was deleted
        XCTAssertEqual(stars([all[1], all[2]]), ["1B", "2C"])
    }

    func testOldFavouritesMoveToNumbersOnce() {
        let all = drinks("A", "B", "C", "D", "E")
        [all[1], all[2], all[3], all[4]].forEach { $0.isFavourite = true }
        XCTAssertTrue(DrinkStars.migrateOldFavourites(all))
        XCTAssertEqual(stars(all), ["1B", "2C", "3D"], "the first three in the user's order")
        XCTAssertFalse(all.contains(where: \.isFavourite))
        DrinkStars.unstar(all[1], in: all)
        XCTAssertFalse(DrinkStars.migrateOldFavourites(all), "doesn't run twice")
        XCTAssertEqual(stars(all), ["1C", "2D"])
    }

    func testWidgetShowsStarsOrElseTheFirstQuickLogDrinks() {
        let all = drinks("A", "B", "C", "D")
        XCTAssertEqual(DrinkStars.widgetDrinks(all).map(\.name), ["A", "B", "C"])
        DrinkStars.star(all[3], in: all)
        XCTAssertEqual(DrinkStars.widgetDrinks(all).map(\.name), ["D"])
    }
}
