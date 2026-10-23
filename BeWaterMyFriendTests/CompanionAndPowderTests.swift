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

    func testHyperAfterEnoughRecentCaffeine() {
        let espresso = entry(.coffee, ml: 30, minutesAgo: 20, caffeinePer100: 210)  // 63 mg
        XCTAssertEqual(CompanionLogic.mood(entries: [espresso], now: now), .calm, "63 mg is below 80 mg")
        let double = entry(.coffee, ml: 60, minutesAgo: 20, caffeinePer100: 210)  // 126 mg
        XCTAssertEqual(CompanionLogic.mood(entries: [double], now: now), .hyper)
    }

    func testCaffeineWearsOffAfterThreeHours() {
        let old = entry(.coffee, ml: 250, minutesAgo: 200, caffeinePer100: 40)
        XCTAssertEqual(CompanionLogic.mood(entries: [old], now: now), .calm)
    }

    func testTipsyBeatsHyper() {
        let coffee = entry(.coffee, ml: 250, minutesAgo: 30, caffeinePer100: 40)
        let beer = entry(.beer, ml: 330, minutesAgo: 30, abv: 5)  // 13 g alcohol
        XCTAssertEqual(CompanionLogic.mood(entries: [coffee, beer], now: now), .tipsy)
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

    func testFillLayersInOrderMergedAndCapped() {
        let entries = [
            entry(.water, ml: 500, minutesAgo: 300),
            entry(.sparklingWater, ml: 500, minutesAgo: 240),  // same colour as water → merged
            entry(.coffee, ml: 250, minutesAgo: 120),
            entry(.beer, ml: 1000, minutesAgo: 60, abv: 5),  // 950 ml counted, but only 750 ml fit
            entry(.water, ml: 500, minutesAgo: 30),  // nothing left to fill
        ]
        let layers = CompanionLogic.fillLayers(entries: entries.shuffled(), goalML: 2000)
        XCTAssertEqual(layers.map(\.tint), [.water, .coffee, .beer])
        XCTAssertEqual(layers[0].fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(layers[1].fraction, 0.125, accuracy: 0.0001)
        XCTAssertEqual(layers[2].fraction, 0.375, accuracy: 0.0001)
        XCTAssertEqual(layers.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.0001)
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
