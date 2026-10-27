import Foundation
import SwiftData

/// A backup file: all drinks, presets, settings and dojo progress, as JSON.
/// Used to move to a new phone or to restore after deleting the app.
nonisolated struct BackupFile: Codable, Sendable {
    static let currentVersion = 1

    struct Drink: Codable, Sendable, Equatable {
        var timestamp: Date
        var name: String
        var category: String
        var volumeML: Double
        var alcoholPercent: Double?
        var hydrationPercent: Double?
        var powderGrams: Double?
        var nutrientsPer100ml: Nutrients
        var source: String
        var barcode: String?
        var healthSyncID: UUID?
        var healthWrittenAt: Date?
    }

    struct Preset: Codable, Sendable, Equatable {
        var name: String
        var category: String
        var volumeML: Double
        var alcoholPercent: Double?
        var hydrationPercent: Double?
        var powderGrams: Double?
        var nutrientsPer100ml: Nutrients
        var isFavourite: Bool
        var sortOrder: Int
        var barcode: String?
        var inQuickLog: Bool
    }

    var version = currentVersion
    var exportedAt: Date
    var drinks: [Drink]
    var presets: [Preset]
    /// Settings and dojo progress (numbers, booleans and strings only).
    var settings: [String: SettingValue]

    enum SettingValue: Codable, Sendable, Equatable {
        case number(Double), bool(Bool), text(String)
    }
}

/// Builds and applies backups.
enum Backup {
    /// Settings that belong in a backup. Internal flags (seeding, repairs,
    /// pending Health deletes, cached calculations) are left out.
    static let settingKeys: [String] = [
        SettingsKey.dailyGoalML, SettingsKey.dayEndMinutes, SettingsKey.companionEnabled,
        SettingsKey.dojoBestGoalDays, SettingsKey.dojoBelt, SettingsKey.prestigeLevel, SettingsKey.prestigeBaseGoalDays,
        SettingsKey.healthWriteDelay, SettingsKey.appearance,
        SettingsKey.reminderStartMinutes, SettingsKey.reminderEndMinutes, SettingsKey.reminderIntervalMinutes,
        SettingsKey.reminderSkipOnTrack, SettingsKey.reminderSmart,
        SettingsKey.goalMode, SettingsKey.weightFromHealth, SettingsKey.manualWeightKg, SettingsKey.goalMlPerKg,
        SettingsKey.useWorkouts, SettingsKey.workoutMlPerHour, SettingsKey.useWeather,
        SettingsKey.heatThresholdC, SettingsKey.heatExtraML, SettingsKey.heatMaxExtraML,
        SettingsKey.coldThresholdC, SettingsKey.coldExtraML, SettingsKey.temperatureUnit,
    ]

    @MainActor
    static func make(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) throws -> BackupFile {
        let entries = try context.fetch(FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        let presets = try context.fetch(FetchDescriptor<DrinkPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
        var settings: [String: BackupFile.SettingValue] = [:]
        for key in settingKeys {
            switch defaults.object(forKey: key) {
            case let b as Bool where CFGetTypeID(b as CFTypeRef) == CFBooleanGetTypeID(): settings[key] = .bool(b)
            case let n as NSNumber: settings[key] = .number(n.doubleValue)
            case let s as String: settings[key] = .text(s)
            default: break
            }
        }
        return BackupFile(
            exportedAt: now,
            drinks: entries.map {
                .init(timestamp: $0.timestamp, name: $0.name, category: $0.categoryRaw, volumeML: $0.volumeML,
                      alcoholPercent: $0.alcoholPercent, hydrationPercent: $0.hydrationPercent, powderGrams: $0.powderGrams,
                      nutrientsPer100ml: $0.nutrientsPer100ml, source: $0.sourceRaw, barcode: $0.barcode,
                      healthSyncID: $0.healthSyncID, healthWrittenAt: $0.healthWrittenAt)
            },
            presets: presets.map {
                .init(name: $0.name, category: $0.categoryRaw, volumeML: $0.volumeML, alcoholPercent: $0.alcoholPercent,
                      hydrationPercent: $0.hydrationPercent, powderGrams: $0.powderGrams,
                      nutrientsPer100ml: $0.nutrientsPer100ml, isFavourite: $0.isFavourite, sortOrder: $0.sortOrder,
                      barcode: $0.barcode, inQuickLog: $0.isInQuickLog)
            },
            settings: settings
        )
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    struct ImportResult: Equatable {
        var addedDrinks = 0
        var skippedDrinks = 0
        var addedPresets = 0
    }

    /// Adds what isn't there yet; existing drinks and presets are kept, so
    /// importing the same file twice changes nothing. Dojo progress only goes up.
    /// Drinks keep their Health state, so drinks already in Apple Health aren't written twice.
    @MainActor
    static func restore(_ file: BackupFile, into context: ModelContext, defaults: UserDefaults = .standard) throws -> ImportResult {
        var result = ImportResult()
        let existing = try context.fetch(FetchDescriptor<DrinkEntry>())
        var keys = Set(existing.map { drinkKey(timestamp: $0.timestamp, name: $0.name, volumeML: $0.volumeML) })
        for d in file.drinks {
            let key = drinkKey(timestamp: d.timestamp, name: d.name, volumeML: d.volumeML)
            guard !keys.contains(key) else { result.skippedDrinks += 1; continue }
            let entry = DrinkEntry(timestamp: d.timestamp, name: d.name,
                                   category: DrinkCategory(rawValue: d.category) ?? .other, volumeML: d.volumeML,
                                   alcoholPercent: d.alcoholPercent, hydrationPercent: d.hydrationPercent,
                                   powderGrams: d.powderGrams, nutrientsPer100ml: d.nutrientsPer100ml,
                                   source: EntrySource(rawValue: d.source) ?? .manual, barcode: d.barcode)
            entry.healthSyncID = d.healthSyncID
            entry.healthWrittenAt = d.healthWrittenAt
            if let written = d.healthWrittenAt { entry.modifiedAt = written }
            context.insert(entry)
            keys.insert(key)
            result.addedDrinks += 1
        }

        var presets = try context.fetch(FetchDescriptor<DrinkPreset>())
        for p in file.presets {
            let category = DrinkCategory(rawValue: p.category) ?? .other
            guard QuickLogRules.existingPreset(barcode: p.barcode, name: p.name, category: category, in: presets) == nil else { continue }
            let preset = DrinkPreset(name: p.name, category: category, volumeML: p.volumeML, alcoholPercent: p.alcoholPercent,
                                     hydrationPercent: p.hydrationPercent, powderGrams: p.powderGrams,
                                     nutrientsPer100ml: p.nutrientsPer100ml, isFavourite: p.isFavourite,
                                     sortOrder: presets.count, barcode: p.barcode)
            preset.isInQuickLog = p.inQuickLog && !QuickLogRules.isFull(presets)
            context.insert(preset)
            presets.append(preset)
            result.addedPresets += 1
        }
        try context.save()
        // Imported drinks can be older than the archive: count everything again.
        if result.addedDrinks > 0 { defaults.removeObject(forKey: SettingsKey.dojoArchive) }

        // Prestige base belongs to the prestige level: only take it from a file
        // with a higher prestige, otherwise ranks would be counted from the wrong point.
        func number(_ key: String) -> Double? {
            if case .number(let n) = file.settings[key] { n } else { nil }
        }
        let filePrestige = number(SettingsKey.prestigeLevel) ?? 0
        if filePrestige > defaults.double(forKey: SettingsKey.prestigeLevel) {
            defaults.set(number(SettingsKey.prestigeBaseGoalDays) ?? 0, forKey: SettingsKey.prestigeBaseGoalDays)
        }

        // Settings: take the backup's values; progress counters only ever go up.
        let progressKeys: Set<String> = [SettingsKey.dojoBestGoalDays, SettingsKey.dojoBelt, SettingsKey.prestigeLevel]
        for (key, value) in file.settings where settingKeys.contains(key) && key != SettingsKey.prestigeBaseGoalDays {
            switch value {
            case .number(let n):
                if progressKeys.contains(key) {
                    defaults.set(max(n, defaults.double(forKey: key)), forKey: key)
                } else {
                    defaults.set(n, forKey: key)
                }
            case .bool(let b): defaults.set(b, forKey: key)
            case .text(let s): defaults.set(s, forKey: key)
            }
        }
        return result
    }

    /// Same drink = same second, name and amount.
    static func drinkKey(timestamp: Date, name: String, volumeML: Double) -> String {
        "\(Int(timestamp.timeIntervalSince1970))|\(QuickLogRules.normalized(name))|\(Int(volumeML.rounded()))"
    }

    static func fileName(now: Date = .now) -> String {
        "BeWaterMyFriend-backup-\(now.formatted(.iso8601.year().month().day()))"
    }
}
