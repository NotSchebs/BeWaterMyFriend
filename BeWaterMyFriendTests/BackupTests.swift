import SwiftData
import XCTest
@testable import BeWaterMyFriend

@MainActor
final class BackupTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testRoundTripToANewPhone() throws {
        let oldPhone = try makeContext()
        let oldDefaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        var nutrients = Nutrients()
        nutrients.caffeineMg = 210
        let espresso = DrinkEntry(timestamp: date(2026, 10, 25, 8), name: "Espresso", category: .coffee,
                                  volumeML: 30, nutrientsPer100ml: nutrients)
        espresso.healthSyncID = UUID()
        espresso.healthWrittenAt = date(2026, 10, 25, 9)
        oldPhone.insert(espresso)
        oldPhone.insert(DrinkPreset(name: "Espresso", category: .coffee, volumeML: 30, isFavourite: true))
        try oldPhone.save()
        oldDefaults.set(2500.0, forKey: SettingsKey.dailyGoalML)
        oldDefaults.set(42, forKey: SettingsKey.dojoBestGoalDays)
        oldDefaults.set(true, forKey: SettingsKey.useWeather)
        oldDefaults.set("suggested", forKey: SettingsKey.goalMode)
        oldDefaults.set(true, forKey: SettingsKey.didSeedPresets)  // internal: must not be exported

        let data = try Backup.encode(Backup.make(context: oldPhone, defaults: oldDefaults))
        let file = try Backup.decode(data)
        XCTAssertNil(file.settings[SettingsKey.didSeedPresets])

        let newPhone = try makeContext()
        let newDefaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let result = try Backup.restore(file, into: newPhone, defaults: newDefaults)
        XCTAssertEqual(result, .init(addedDrinks: 1, skippedDrinks: 0, addedPresets: 1))

        let restored = try XCTUnwrap(newPhone.fetch(FetchDescriptor<DrinkEntry>()).first)
        XCTAssertEqual(restored.caffeineMg, 63, accuracy: 0.001)
        XCTAssertFalse(restored.needsHealthWrite, "already in Health: not written twice")
        XCTAssertEqual(newDefaults.double(forKey: SettingsKey.dailyGoalML), 2500)
        XCTAssertEqual(newDefaults.integer(forKey: SettingsKey.dojoBestGoalDays), 42)
        XCTAssertTrue(newDefaults.bool(forKey: SettingsKey.useWeather))
        XCTAssertEqual(newDefaults.string(forKey: SettingsKey.goalMode), "suggested")
    }

    func testImportingTwiceAddsNothingAndProgressNeverGoesDown() throws {
        let context = try makeContext()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        context.insert(DrinkEntry(timestamp: date(2026, 10, 25, 8), name: "Water", category: .water, volumeML: 250))
        try context.save()
        defaults.set(10, forKey: SettingsKey.dojoBestGoalDays)
        let file = try Backup.make(context: context, defaults: defaults)

        defaults.set(50, forKey: SettingsKey.dojoBestGoalDays)  // progressed since the backup
        let result = try Backup.restore(file, into: context, defaults: defaults)
        XCTAssertEqual(result.addedDrinks, 0)
        XCTAssertEqual(result.skippedDrinks, 1)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.dojoBestGoalDays), 50)
    }

    func testPrestigeBaseOnlyComesWithAHigherPrestige() throws {
        let context = try makeContext()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(3, forKey: SettingsKey.prestigeLevel)
        defaults.set(3000, forKey: SettingsKey.prestigeBaseGoalDays)
        defaults.set(4000, forKey: SettingsKey.dojoBestGoalDays)
        // An old backup from before any prestige must not reset the base.
        let old = BackupFile(exportedAt: .now, drinks: [], presets: [], settings: [
            SettingsKey.prestigeLevel: .number(0), SettingsKey.prestigeBaseGoalDays: .number(0),
            SettingsKey.dojoBestGoalDays: .number(35),
        ])
        _ = try Backup.restore(old, into: context, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.prestigeBaseGoalDays), 3000)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.prestigeLevel), 3)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.dojoBestGoalDays), 4000)
        // A backup with a higher prestige brings its own base.
        let newer = BackupFile(exportedAt: .now, drinks: [], presets: [], settings: [
            SettingsKey.prestigeLevel: .number(4), SettingsKey.prestigeBaseGoalDays: .number(4200),
        ])
        _ = try Backup.restore(newer, into: context, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.prestigeBaseGoalDays), 4200)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try Backup.decode(Data(#"{"hello":"world"}"#.utf8)))
    }
}
