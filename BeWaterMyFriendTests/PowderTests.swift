import XCTest
@testable import BeWaterMyFriend

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

    func testReadyToDrinkProteinShakeIsAProteinDrink() throws {
        let json = #"""
        {"code":"7610000000002","status":1,"product":{"product_name":"High Protein Drink Vanilla","quantity":"330 ml",
        "product_quantity":330,"product_quantity_unit":"ml","nutrition_data_per":"100ml","categories_tags":["en:dairies","en:milks"],
        "nutriments":{"proteins_100g":7.5}}}
        """#
        let product = try XCTUnwrap(OpenFoodFacts.parse(Data(json.utf8), barcode: "7610000000002"))
        XCTAssertEqual(product.category, .proteinDrink)
        XCTAssertNil(product.powderGrams, "no scoop for ready-to-drink")
        XCTAssertEqual(product.suggestedVolumeML, 330)
    }

    func testMissingCaffeineIsPointedOutForCola() throws {
        let product = try XCTUnwrap(OpenFoodFacts.parse(Data(OFFFixtures.cocaCola.utf8), barcode: "5449000000996"))
        XCTAssertTrue(DrinkDraft(scanned: product).scanNote?.contains("Caffeine isn't listed") ?? false)
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
