import SwiftData
import XCTest
@testable import BeWaterMyFriend

@MainActor
final class ScanTests: XCTestCase {
    private func parse(_ json: String, _ code: String) throws -> ScannedProduct? {
        try OpenFoodFacts.parse(Data(json.utf8), barcode: code)
    }

    // MARK: Parsing real responses

    func testRedBullCaffeineAndVitaminsAreConvertedFromGrams() throws {
        let product = try XCTUnwrap(parse(OFFFixtures.redBull, "9002490100070"))
        XCTAssertEqual(product.name, "Red Bull")
        XCTAssertEqual(product.category, .energyDrink, "energy drink wins over soda")
        XCTAssertEqual(product.suggestedVolumeML, 250)
        XCTAssertEqual(try XCTUnwrap(product.nutrientsPer100ml.caffeineMg), 32, accuracy: 0.0001)  // 0.032 g
        XCTAssertEqual(try XCTUnwrap(product.nutrientsPer100ml.sodiumMg), 40, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(product.nutrientsPer100ml.vitaminB12Mcg), 2, accuracy: 0.0001)  // 2e-6 g
        XCTAssertEqual(try XCTUnwrap(product.nutrientsPer100ml.niacinMg), 8, accuracy: 0.0001)  // vitamin-pp
        XCTAssertEqual(product.nutrientsPer100ml.sugarG, 11)
        XCTAssertEqual(product.nutrientsPer100ml.energyKcal, 46)
        XCTAssertFalse(product.valuesWerePer100g)
        XCTAssertNil(product.alcoholPercent)
    }

    func testBeerKegGetsAlcoholAndATypicalServingInsteadOfFiveLitres() throws {
        let product = try XCTUnwrap(parse(OFFFixtures.heinekenKeg, "8712000025649"))
        XCTAssertEqual(product.category, .beer)
        XCTAssertEqual(product.alcoholPercent, 5)
        XCTAssertEqual(product.packageVolumeML, 5000)
        XCTAssertEqual(product.suggestedVolumeML, 330)
        XCTAssertTrue(product.valuesWerePer100g)
    }

    func testSwissRivella() throws {
        let product = try XCTUnwrap(parse(OFFFixtures.rivellaRot, "7610097111072"))
        XCTAssertEqual(product.category, .softDrink)
        XCTAssertEqual(product.suggestedVolumeML, 500)
        XCTAssertEqual(try XCTUnwrap(product.nutrientsPer100ml.sodiumMg), 12, accuracy: 0.0001)
    }

    func testMissingCaffeineStaysUnknown() throws {
        // Coca-Cola's entry has no caffeine value; it must not become 0.
        let product = try XCTUnwrap(parse(OFFFixtures.cocaCola, "5449000000996"))
        XCTAssertNil(product.nutrientsPer100ml.caffeineMg)
        XCTAssertEqual(product.suggestedVolumeML, 330)
    }

    func testUnknownProductReturnsNil() throws {
        XCTAssertNil(try parse(OFFFixtures.notFound, "7613035833128"))
    }

    func testHTMLErrorPageThrows() {
        XCTAssertThrowsError(try parse("<!DOCTYPE html><title>Page temporarily unavailable</title>", "5449000000996"))
    }

    // MARK: Helpers

    func testBarcodeValidation() {
        XCTAssertTrue(OpenFoodFacts.isValidBarcode("7610097111072"))
        XCTAssertTrue(OpenFoodFacts.isValidBarcode("12345670"))
        XCTAssertFalse(OpenFoodFacts.isValidBarcode("123"))
        XCTAssertFalse(OpenFoodFacts.isValidBarcode("76100971110a2"))
        XCTAssertFalse(OpenFoodFacts.isValidBarcode("761009711107٢"), "non-ASCII digits")
        XCTAssertNil(OpenFoodFacts.url(for: "abc"))
    }

    func testVolumeParsing() {
        XCTAssertEqual(OpenFoodFacts.volumeML(quantity: "33 cl", productQuantity: nil, unit: nil), 330)
        XCTAssertEqual(OpenFoodFacts.volumeML(quantity: "0.5l", productQuantity: nil, unit: nil), 500)
        XCTAssertEqual(OpenFoodFacts.volumeML(quantity: "1,5 L", productQuantity: nil, unit: nil), 1500)
        XCTAssertEqual(OpenFoodFacts.volumeML(quantity: "6 x 330 ml", productQuantity: nil, unit: nil), 330)
        XCTAssertEqual(OpenFoodFacts.volumeML(quantity: "irrelevant", productQuantity: 2, unit: "l"), 2000)
        XCTAssertNil(OpenFoodFacts.volumeML(quantity: "a bottle", productQuantity: nil, unit: nil))
    }

    func testCategoryGuessFallsBackToAlcoholStrength() {
        XCTAssertEqual(OpenFoodFacts.guessCategory(tags: ["en:mineral-waters", "en:carbonated-waters"], alcoholPercent: nil), .sparklingWater)
        XCTAssertEqual(OpenFoodFacts.guessCategory(tags: ["en:iced-teas"], alcoholPercent: nil), .tea)
        XCTAssertEqual(OpenFoodFacts.guessCategory(tags: [], alcoholPercent: 12.5), .wine)
        XCTAssertEqual(OpenFoodFacts.guessCategory(tags: [], alcoholPercent: 40), .spirits)
        XCTAssertEqual(OpenFoodFacts.guessCategory(tags: [], alcoholPercent: nil), .other)
    }

    // MARK: Review and remembering

    func testScannedDraftIsMarkedAsScanAndRemembered() throws {
        let product = try XCTUnwrap(parse(OFFFixtures.redBull, "9002490100070"))
        let draft = DrinkDraft(scanned: product)
        XCTAssertTrue(draft.saveAsPreset)
        XCTAssertNotNil(draft.scanNote)
        let entry = draft.makeEntry()
        XCTAssertEqual(entry.source, .scan)
        XCTAssertEqual(entry.barcode, "9002490100070")
        XCTAssertEqual(entry.caffeineMg, 80, accuracy: 0.0001)  // 250 ml × 32 mg/100 ml
    }

    func testCorrectedPresetIsFoundByBarcode() throws {
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        var draft = DrinkDraft(unknownBarcode: "7610097111072")
        draft.name = "Rivella Rot"
        draft.category = .softDrink
        draft.volumeML = 500
        context.insert(draft.makePreset(sortOrder: 0))
        try context.save()

        let code: String? = "7610097111072"
        let found = try context.fetch(FetchDescriptor<DrinkPreset>(predicate: #Predicate { $0.barcode == code }))
        XCTAssertEqual(found.map(\.name), ["Rivella Rot"])
        XCTAssertEqual(found.first?.makeEntry().source, .scan)
        XCTAssertTrue(DrinkDraft(scannedPreset: try XCTUnwrap(found.first)).saveAsPreset,
                      "corrections on a rescan update the saved version")
    }
}
