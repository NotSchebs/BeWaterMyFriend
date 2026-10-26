import SwiftData
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

final class LogTimeLimitTests: XCTestCase {
    func testDrinksCanGoBackTwoDaysNotMore() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        let now = date(2026, 10, 26, 15, 0)
        XCTAssertEqual(LogTimeLimit.earliest(now: now, boundary: boundary), date(2026, 10, 24, 0, 0))
        let range = LogTimeLimit.range(now: now, boundary: boundary)
        XCTAssertTrue(range.contains(date(2026, 10, 24, 8, 0)))
        XCTAssertFalse(range.contains(date(2026, 10, 23, 23, 0)))
        XCTAssertFalse(range.contains(date(2026, 10, 26, 16, 0)), "no future drinks")
    }

    func testCustomDayEndIsRespected() {
        let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)
        // At 01:00 on 26 Oct the logical day is still 25 Oct → earliest is 23 Oct 03:00.
        XCTAssertEqual(LogTimeLimit.earliest(now: date(2026, 10, 26, 1, 0), boundary: boundary), date(2026, 10, 23, 3, 0))
    }

    func testOlderEntryKeepsItsOwnTimeAsLowerBound() {
        let boundary = DayBoundary(dayEndMinutes: 0, calendar: zurich)
        let old = date(2026, 10, 10, 12, 0)
        let range = LogTimeLimit.range(now: date(2026, 10, 26, 15, 0), boundary: boundary, existing: old)
        XCTAssertEqual(range.lowerBound, old)
    }
}

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
