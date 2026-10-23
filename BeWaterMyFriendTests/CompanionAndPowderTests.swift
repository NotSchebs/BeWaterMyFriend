import XCTest
@testable import BeWaterMyFriend

@MainActor
final class CompanionTests: XCTestCase {
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

    func testHyperWhenLastDrinkHadCaffeine() {
        let espresso = entry(.coffee, ml: 30, minutesAgo: 20, caffeinePer100: 210)
        XCTAssertEqual(CompanionLogic.mood(entries: [espresso], now: now), .hyper)
    }

    func testMoodFollowsTheLastDrink() {
        let coffee = entry(.coffee, ml: 250, minutesAgo: 60, caffeinePer100: 40)
        let water = entry(.water, ml: 250, minutesAgo: 10)
        XCTAssertEqual(CompanionLogic.mood(entries: [coffee, water], now: now), .calm, "water after coffee calms it")
        let shake = entry(.proteinShake, ml: 300, minutesAgo: 5)
        XCTAssertEqual(CompanionLogic.mood(entries: [coffee, water, shake], now: now), .strong)
    }

    func testCaffeineWearsOffAfterThreeHours() {
        let old = entry(.coffee, ml: 250, minutesAgo: 200, caffeinePer100: 40)
        XCTAssertEqual(CompanionLogic.mood(entries: [old], now: now), .calm)
    }

    func testTipsyWhenLastDrinkWasAlcoholic() {
        let beer = entry(.beer, ml: 330, minutesAgo: 30, abv: 5)
        XCTAssertEqual(CompanionLogic.mood(entries: [beer], now: now), .tipsy)
        let coffeeAfter = entry(.coffee, ml: 250, minutesAgo: 10, caffeinePer100: 40)
        XCTAssertEqual(CompanionLogic.mood(entries: [beer, coffeeAfter], now: now), .hyper)
    }

    func testTooMuchAlcoholMakesItDrunkWhateverCameLast() {
        // 3 beers × 1.3 standard drinks within 3 hours, then a water.
        let beers = (0..<3).map { entry(.beer, ml: 330, minutesAgo: 120 - Double($0) * 30, abv: 5) }
        let water = entry(.water, ml: 250, minutesAgo: 5)
        XCTAssertEqual(CompanionLogic.mood(entries: beers + [water], now: now), .drunk)
        // Two beers (2.6 standard drinks) are not enough.
        XCTAssertEqual(CompanionLogic.mood(entries: Array(beers.prefix(2)), now: now), .tipsy)
        // Three beers more than 3 hours ago no longer count.
        let old = (0..<3).map { entry(.beer, ml: 330, minutesAgo: 240 + Double($0) * 10, abv: 5) }
        XCTAssertEqual(CompanionLogic.mood(entries: old, now: now), .calm)
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
        XCTAssertEqual(CompanionLogic.mood(entries: [entry(.proteinShake, ml: 300, minutesAgo: 150)], now: now), .calm)
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

@MainActor
final class PowderTests: XCTestCase {
    /// 375 mg magnesium per 100 g of powder (as on many electrolyte tubs).
    private func electrolytes(scoop: Double, water: Double) -> DrinkEntry {
        var nutrients = Nutrients()
        nutrients.magnesiumMg = 375
        nutrients.sodiumMg = 5000
        return DrinkEntry(name: "Electrolytes", category: .electrolytes, volumeML: water,
                          powderGrams: scoop, nutrientsPer100ml: nutrients)
    }

    func testNutrientsScaleWithPowderAndWaterWithLiquid() throws {
        let drink = electrolytes(scoop: 8, water: 500)
        XCTAssertEqual(try XCTUnwrap(drink.amount(of: .magnesium)), 30, accuracy: 0.0001)  // 8 g × 375/100
        XCTAssertEqual(drink.hydrationML, 500)
    }

    func testDailyTotalsAndHealthUsePowderGrams() throws {
        let drink = electrolytes(scoop: 8, water: 500)
        let day = Summaries.daily(entries: [drink], boundary: DayBoundary(calendar: zurich))[0]
        XCTAssertEqual(try XCTUnwrap(day.nutrientTotals[.magnesium]), 30, accuracy: 0.0001)
        XCTAssertEqual(day.goalFluidML, 500)
        let samples = HealthPlan.samples(for: drink)
        XCTAssertEqual(try XCTUnwrap(samples.first { $0.quantity == .nutrient(.sodium) }?.value), 400, accuracy: 0.0001)
        XCTAssertEqual(samples.first { $0.quantity == .water }?.value, 500)
    }

    func testDraftUsesTypicalScoopAndDropsPowderForNormalDrinks() {
        var draft = DrinkDraft()
        draft.name = "Whey"
        draft.category = .proteinShake
        XCTAssertEqual(draft.effectivePowderGrams, 30)
        draft.powderGrams = 25
        XCTAssertEqual(draft.makeEntry().powderGrams, 25)
        draft.category = .water
        XCTAssertNil(draft.makeEntry().powderGrams)
    }

    func testScannedElectrolytePowder() throws {
        let json = #"""
        {"code":"7610000000001","status":1,"product":{"product_name":"Elektrolyt Pulver Zitrone","quantity":"200 g",
        "product_quantity":200,"product_quantity_unit":"g","serving_size":"8 g","serving_quantity":8,
        "nutrition_data_per":"100g","categories_tags":["en:dietary-supplements"],
        "nutriments":{"magnesium_100g":0.375,"sodium_100g":5,"energy-kcal_100g":350}}}
        """#
        let product = try XCTUnwrap(OpenFoodFacts.parse(Data(json.utf8), barcode: "7610000000001"))
        XCTAssertEqual(product.category, .electrolytes)
        XCTAssertEqual(product.powderGrams, 8)
        XCTAssertEqual(product.suggestedVolumeML, 500)
        XCTAssertEqual(try XCTUnwrap(product.nutrientsPer100ml.magnesiumMg), 375, accuracy: 0.0001)
        let entry = DrinkDraft(scanned: product).makeEntry()
        XCTAssertEqual(try XCTUnwrap(entry.amount(of: .magnesium)), 30, accuracy: 0.0001)
    }

    func testPowderDetection() {
        XCTAssertEqual(OpenFoodFacts.powderCategory(name: "Whey Protein Vanilla", tags: [], unit: "g"), .proteinShake)
        XCTAssertEqual(OpenFoodFacts.powderCategory(name: "Iso Drink", tags: ["en:electrolyte-powders"], unit: nil), .electrolytes)
        XCTAssertNil(OpenFoodFacts.powderCategory(name: "Heineken", tags: ["en:beers"], unit: "g"), "keg sold by weight isn't a powder")
        XCTAssertNil(OpenFoodFacts.powderCategory(name: "Protein Drink", tags: [], unit: "ml"), "ready-to-drink isn't a powder")
        XCTAssertEqual(OpenFoodFacts.scoopGrams(servingSize: "1 scoop (30 g)", servingQuantity: nil), 30)
        XCTAssertEqual(OpenFoodFacts.scoopGrams(servingSize: "8,5 g", servingQuantity: nil), 8.5)
        XCTAssertNil(OpenFoodFacts.scoopGrams(servingSize: "250 ml", servingQuantity: 250))
    }
}
