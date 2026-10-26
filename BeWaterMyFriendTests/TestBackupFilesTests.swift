import SwiftData
import XCTest
@testable import BeWaterMyFriend

/// Builds the three test backups with the app's own types (so they're exactly
/// what an export looks like), imports each into a fresh "phone", and checks
/// the restored rank. Set BWMF_WRITE_TEST_BACKUPS to a folder to also save them.
@MainActor
final class TestBackupFilesTests: XCTestCase {
    struct Profile {
        var file: String
        var bestGoalDays: Int
        var belt: Belt
        var prestige: Int
        var prestigeBase: Int
    }

    static let profiles = [
        Profile(file: "1-blue-belt", bestGoalDays: 35, belt: .blue, prestige: 0, prestigeBase: 0),
        Profile(file: "2-second-dan", bestGoalDays: 210, belt: .dan2, prestige: 0, prestigeBase: 0),
        Profile(file: "3-prestige3-tenth-dan", bestGoalDays: 4000, belt: .dan10, prestige: 3, prestigeBase: 3000),
    ]

    private func makeFile(_ p: Profile, now: Date) -> BackupFile {
        let calendar = Calendar.current
        // Two weeks of drinks so History and Stats have something to show.
        var drinks: [BackupFile.Drink] = []
        for daysAgo in 1...14 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            for (hour, ml, name, category) in [(9, 500.0, "Bottle of water", "water"), (13, 250.0, "Glass of water", "water"),
                                               (16, 250.0, "Coffee", "coffee"), (19, 500.0, "Bottle of water", "water")] {
                var nutrients = Nutrients()
                if category == "coffee" { nutrients.caffeineMg = 40 }
                drinks.append(.init(timestamp: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!,
                                    name: name, category: category, volumeML: ml, alcoholPercent: nil,
                                    hydrationPercent: nil, powderGrams: nil, nutrientsPer100ml: nutrients,
                                    source: "preset", barcode: nil,
                                    // Marked as already in Health, so importing never writes test drinks to Health.
                                    healthSyncID: UUID(), healthWrittenAt: now))
            }
        }
        return BackupFile(exportedAt: now, drinks: drinks, presets: [], settings: [
            SettingsKey.dojoBestGoalDays: .number(Double(p.bestGoalDays)),
            SettingsKey.dojoBelt: .number(Double(p.belt.rawValue)),
            SettingsKey.prestigeLevel: .number(Double(p.prestige)),
            SettingsKey.prestigeBaseGoalDays: .number(Double(p.prestigeBase)),
            SettingsKey.dailyGoalML: .number(1500),
        ])
    }

    func testEachTestBackupRestoresItsRank() throws {
        let now = Date.now
        let folder = ProcessInfo.processInfo.environment["BWMF_WRITE_TEST_BACKUPS"]
        for profile in Self.profiles {
            let data = try Backup.encode(makeFile(profile, now: now))
            if let folder {
                try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(profile.file).json"))
            }
            let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = ModelContext(container)
            let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
            let result = try Backup.restore(Backup.decode(data), into: context, defaults: defaults)

            XCTAssertEqual(result.addedDrinks, 56, profile.file)
            let rankDays = DojoProgress.rankGoalDays(bestTotal: defaults.integer(forKey: SettingsKey.dojoBestGoalDays),
                                                     currentTotal: 0,
                                                     prestigeBase: defaults.integer(forKey: SettingsKey.prestigeBaseGoalDays))
            XCTAssertEqual(Belt.belt(forGoalDays: rankDays), profile.belt, profile.file)
            XCTAssertEqual(defaults.integer(forKey: SettingsKey.prestigeLevel), profile.prestige, profile.file)
            let drinks = try context.fetch(FetchDescriptor<DrinkEntry>())
            XCTAssertTrue(drinks.allSatisfy { !$0.needsHealthWrite }, "test drinks must not go to Health")
        }
    }
}
