import SwiftData
import XCTest
@testable import BeWaterMyFriend

@MainActor
final class ModelTests: XCTestCase {
    func testEditingVolumeRecalculatesNutrients() {
        var nutrients = Nutrients()
        nutrients.caffeineMg = 10
        let entry = DrinkEntry(name: "Cola", category: .softDrink, volumeML: 330, nutrientsPer100ml: nutrients)
        XCTAssertEqual(entry.caffeineMg, 33, accuracy: 0.0001)
        entry.volumeML = 500
        XCTAssertEqual(entry.caffeineMg, 50, accuracy: 0.0001)
    }

    func testEntryFromPresetIsAnIndependentCopy() {
        let preset = DrinkPreset(name: "Espresso", category: .coffee, volumeML: 30)
        let entry = preset.makeEntry(at: date(2026, 10, 16, 8))
        preset.volumeML = 60
        preset.name = "Double espresso"
        XCTAssertEqual(entry.volumeML, 30)
        XCTAssertEqual(entry.name, "Espresso")
        XCTAssertEqual(entry.source, .preset)
    }

    func testDraftDropsAlcoholForNonAlcoholicCategory() {
        var draft = DrinkDraft()
        draft.name = "Juice"
        draft.category = .juice
        draft.alcoholPercent = 5
        XCTAssertNil(draft.makeEntry().alcoholPercent)
    }

    func testDraftTrimsAndValidatesName() {
        var draft = DrinkDraft()
        draft.name = "   "
        XCTAssertFalse(draft.isValid)
        draft.name = "  Tea "
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.makeEntry().name, "Tea")
        draft.volumeML = 0
        XCTAssertFalse(draft.isValid)
    }

    func testNutrientSubscriptCoversEveryField() {
        var nutrients = Nutrients()
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            nutrients[nutrient] = Double(index + 1)
        }
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            XCTAssertEqual(nutrients[nutrient], Double(index + 1), "\(nutrient) maps to a shared or wrong field")
        }
    }

    /// Saves to a real SQLite file and reads it back with a fresh container,
    /// including an entry whose nutrients are all unknown.
    func testEntriesSurviveSaveAndReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: url) }

        var nutrients = Nutrients()
        nutrients.caffeineMg = 210
        nutrients.magnesiumMg = 1.5

        do {
            let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                               configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(DrinkEntry(timestamp: date(2026, 10, 16, 8), name: "Espresso", category: .coffee,
                                      volumeML: 30, nutrientsPer100ml: nutrients))
            context.insert(DrinkEntry(timestamp: date(2026, 10, 16, 9), name: "Water", category: .water, volumeML: 250))
            context.insert(DrinkEntry(timestamp: date(2026, 10, 16, 20), name: "Beer", category: .beer,
                                      volumeML: 330, alcoholPercent: 5))
            try context.save()
        }

        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(url: url))
        let entries = try ModelContext(container).fetch(FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp)]))

        XCTAssertEqual(entries.map(\.name), ["Espresso", "Water", "Beer"])
        XCTAssertEqual(entries[0].category, .coffee)
        XCTAssertEqual(entries[0].nutrientsPer100ml, nutrients)
        XCTAssertEqual(entries[0].caffeineMg, 63, accuracy: 0.0001)
        XCTAssertTrue(entries[1].nutrientsPer100ml.isEmpty)
        XCTAssertNil(entries[1].alcoholPercent)
        XCTAssertEqual(entries[2].alcoholPercent, 5)
    }

    func testDefaultPresetsAreSeededOnlyOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        DefaultPresets.seedIfNeeded(in: context, defaults: defaults)
        let seeded = try context.fetch(FetchDescriptor<DrinkPreset>())
        XCTAssertEqual(seeded.count, DefaultPresets.make().count)

        // User deletes all presets; they must not come back on next launch.
        seeded.forEach { context.delete($0) }
        try context.save()
        DefaultPresets.seedIfNeeded(in: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DrinkPreset>()), 0)
    }
}
