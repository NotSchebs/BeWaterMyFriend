import SwiftData
import XCTest
@testable import BeWaterMyFriend

/// `Fixtures/DrinksV1.store` was saved with the app as it was before database
/// versions existed, like the databases on real phones. If a future change can't
/// open it or loses something, this fails before it ever reaches a phone.
@MainActor
final class DatabaseUpgradeTests: XCTestCase {
    private func openSample() throws -> (ModelContainer, URL) {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "DrinksV1", withExtension: "store")
                                   ?? bundle.url(forResource: "DrinksV1", withExtension: "store", subdirectory: "Fixtures"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("default.store")
        try FileManager.default.copyItem(at: source, to: url)
        return (try DrinkDatabase.makeContainer(configuration: ModelConfiguration(url: url)), url)
    }

    func testOldDatabaseOpensWithEverythingInIt() throws {
        let (container, _) = try openSample()
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        XCTAssertEqual(entries.map(\.name), ["Coffee", "Water", "Beer", "Electrolytes"])

        let coffee = entries[0]
        XCTAssertEqual(coffee.category, .coffee)
        XCTAssertEqual(coffee.volumeML, 250)
        XCTAssertEqual(coffee.nutrientsPer100ml.caffeineMg, 40)
        XCTAssertEqual(coffee.nutrientsPer100ml.sugarG, 1.5)
        XCTAssertEqual(coffee.source, .preset)
        XCTAssertEqual(coffee.healthSyncID, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertNotNil(coffee.healthWrittenAt, "or everything would be written to Health twice")

        XCTAssertNil(entries[1].nutrientsPer100ml.caffeineMg, "unknown stays unknown, not 0")
        XCTAssertEqual(entries[2].alcoholPercent, 5)
        XCTAssertEqual(entries[2].hydrationPercent, 80)
        XCTAssertEqual(entries[3].powderGrams, 8)
        XCTAssertEqual(entries[3].barcode, "7610000000017")

        let presets = try context.fetch(FetchDescriptor<DrinkPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(presets.map(\.name), ["Glass of water", "Hidden", "Old favourite"])
        XCTAssertEqual(presets[0].starNumber, 1)
        XCTAssertFalse(presets[1].isInQuickLog)
        XCTAssertEqual(presets[1].barcode, "7610097111072")
        XCTAssertTrue(presets[2].isFavourite, "still waiting for its one-time move to a numbered star")
    }

    func testUpgradedDatabaseKeepsWorkingAcrossRestarts() throws {
        var (container, url) = try openSample()
        var context = ModelContext(container)
        context.insert(DrinkEntry(name: "New", category: .water, volumeML: 100))
        try context.save()

        container = try DrinkDatabase.makeContainer(configuration: ModelConfiguration(url: url))
        context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DrinkEntry>()), 5)
    }

    /// A reminder, not a rule against changes: when this fails, a field changed.
    /// A new optional field: just add it here. Anything else needs a new schema
    /// version first (see `DrinkSchema.swift`), or real phones could lose data.
    func testDatabaseStructureDidNotChangeByAccident() {
        let schema = Schema(versionedSchema: DrinkSchemaV1.self)
        let found = Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
            (entity.name, (entity.attributes.map(\.name) + entity.relationships.map(\.name)).sorted())
        })
        XCTAssertEqual(found["DrinkEntry"], ["alcoholPercent", "barcode", "categoryRaw", "healthSyncID", "healthWrittenAt",
                                             "hydrationPercent", "modifiedAt", "name", "nutrientsData", "powderGrams",
                                             "sourceRaw", "timestamp", "volumeML"])
        XCTAssertEqual(found["DrinkPreset"], ["alcoholPercent", "barcode", "categoryRaw", "hydrationPercent", "inQuickLog",
                                              "isFavourite", "name", "nutrientsData", "powderGrams", "sortOrder",
                                              "starNumber", "volumeML"])
    }
}
