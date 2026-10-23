import Foundation
import SwiftData

/// One logged drink. Every drink becomes an entry, whether it was entered
/// manually, tapped from a preset, or (later) scanned.
///
/// Nutrients are stored **per 100 ml**; totals are always calculated from the
/// current volume, so editing the amount can never leave stale nutrient totals.
@Model
final class DrinkEntry {
    /// The exact moment of the drink. Which logical day it belongs to is
    /// calculated from this and the user's day end, never stored.
    var timestamp: Date
    var name: String
    /// Stored as the raw string so SwiftData can filter and sort on it.
    var categoryRaw: String
    var volumeML: Double
    /// Alcohol by volume in percent (5 for a 5 % beer). `nil` for non-alcoholic.
    var alcoholPercent: Double?
    /// Share of the drink that counts toward the water goal, in percent.
    /// `nil` means automatic (see `DrinkMath.defaultHydrationPercent`).
    var hydrationPercent: Double?
    /// Encoded `Nutrients`. See `NutrientStorage` for why this isn't stored directly.
    var nutrientsData: Data?
    var sourceRaw: String

    // Apple Health sync. All optional so existing databases migrate without data loss.
    /// When the entry was created or last edited. Restarts the Health write delay.
    var modifiedAt: Date?
    /// Tags every Health sample written for this entry, so they can be found and deleted.
    var healthSyncID: UUID?
    /// The `modifiedAt` of the version last written to Health (so an edit made
    /// while a write is in progress is still detected). `nil` = never written.
    var healthWrittenAt: Date?

    init(
        timestamp: Date = .now,
        name: String,
        category: DrinkCategory,
        volumeML: Double,
        alcoholPercent: Double? = nil,
        hydrationPercent: Double? = nil,
        nutrientsPer100ml: Nutrients = Nutrients(),
        source: EntrySource = .manual
    ) {
        self.timestamp = timestamp
        self.name = name
        self.categoryRaw = category.rawValue
        self.volumeML = volumeML
        self.alcoholPercent = alcoholPercent
        self.hydrationPercent = hydrationPercent
        self.nutrientsData = NutrientStorage.encode(nutrientsPer100ml)
        self.sourceRaw = source.rawValue
        self.modifiedAt = .now
    }

    var category: DrinkCategory {
        get { DrinkCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Nutrient values per 100 ml.
    var nutrientsPer100ml: Nutrients {
        get { NutrientStorage.decode(nutrientsData) }
        set { nutrientsData = NutrientStorage.encode(newValue) }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Total amount of a nutrient in this drink, or `nil` if unknown.
    func amount(of nutrient: Nutrient) -> Double? {
        DrinkMath.scale(nutrientsPer100ml[nutrient], toVolumeML: volumeML)
    }

    var caffeineMg: Double { amount(of: .caffeine) ?? 0 }

    var alcoholGrams: Double {
        DrinkMath.alcoholGrams(volumeML: volumeML, alcoholPercent: alcoholPercent)
    }

    /// The percentage actually used: the user's value, or the automatic default.
    var effectiveHydrationPercent: Double {
        hydrationPercent ?? DrinkMath.defaultHydrationPercent(category: category, alcoholPercent: alcoholPercent)
    }

    /// Millilitres that count toward the water goal.
    var hydrationML: Double {
        DrinkMath.hydrationML(volumeML: volumeML, percent: effectiveHydrationPercent)
    }

    /// True when Health doesn't have the current version of this entry yet.
    var needsHealthWrite: Bool {
        guard let healthWrittenAt else { return true }
        return (modifiedAt ?? timestamp) > healthWrittenAt
    }
}

/// A reusable template ("Espresso, 30 ml"). Tapping it creates a new entry by
/// copying the values, so editing a preset later never changes past entries.
@Model
final class DrinkPreset {
    var name: String
    var categoryRaw: String
    var volumeML: Double
    var alcoholPercent: Double?
    /// `nil` = automatic, like on `DrinkEntry`.
    var hydrationPercent: Double?
    /// Encoded `Nutrients`. See `NutrientStorage` for why this isn't stored directly.
    var nutrientsData: Data?
    var isFavourite: Bool
    var sortOrder: Int

    init(
        name: String,
        category: DrinkCategory,
        volumeML: Double,
        alcoholPercent: Double? = nil,
        hydrationPercent: Double? = nil,
        nutrientsPer100ml: Nutrients = Nutrients(),
        isFavourite: Bool = false,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.volumeML = volumeML
        self.alcoholPercent = alcoholPercent
        self.hydrationPercent = hydrationPercent
        self.nutrientsData = NutrientStorage.encode(nutrientsPer100ml)
        self.isFavourite = isFavourite
        self.sortOrder = sortOrder
    }

    var category: DrinkCategory {
        get { DrinkCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var nutrientsPer100ml: Nutrients {
        get { NutrientStorage.decode(nutrientsData) }
        set { nutrientsData = NutrientStorage.encode(newValue) }
    }

    /// Creates a new, independent entry from this preset.
    func makeEntry(at timestamp: Date = .now) -> DrinkEntry {
        DrinkEntry(
            timestamp: timestamp,
            name: name,
            category: category,
            volumeML: volumeML,
            alcoholPercent: alcoholPercent,
            hydrationPercent: hydrationPercent,
            nutrientsPer100ml: nutrientsPer100ml,
            source: .preset
        )
    }
}

/// Saves `Nutrients` as one encoded value.
///
/// Storing the struct directly as a SwiftData property crashed on reload when
/// every nutrient was `nil` (e.g. plain water): SwiftData read the empty struct
/// back as `nil` and failed to cast it ("Could not cast Optional<Any> to
/// Nutrients"). Encoding it ourselves avoids that; we never filter by nutrient
/// in a database query, so nothing is lost.
nonisolated enum NutrientStorage {
    static func encode(_ nutrients: Nutrients) -> Data? {
        nutrients.isEmpty ? nil : try? JSONEncoder().encode(nutrients)
    }

    static func decode(_ data: Data?) -> Nutrients {
        guard let data, let nutrients = try? JSONDecoder().decode(Nutrients.self, from: data) else {
            return Nutrients()
        }
        return nutrients
    }
}
