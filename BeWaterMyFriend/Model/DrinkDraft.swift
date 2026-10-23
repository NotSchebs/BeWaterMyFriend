import Foundation

/// Editable copy of an entry or preset used by the editor screens.
/// Editing a draft instead of the live model means "Cancel" really discards
/// changes, and nothing half-edited is ever saved.
struct DrinkDraft {
    var timestamp: Date = .now
    var name: String = ""
    var category: DrinkCategory = .water
    var volumeML: Double = 250
    var alcoholPercent: Double?
    /// `nil` = automatic.
    var hydrationPercent: Double?
    var nutrientsPer100ml = Nutrients()
    var isFavourite = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && volumeML > 0
    }

    init() {}

    init(entry: DrinkEntry) {
        timestamp = entry.timestamp
        name = entry.name
        category = entry.category
        volumeML = entry.volumeML
        alcoholPercent = entry.alcoholPercent
        hydrationPercent = entry.hydrationPercent
        nutrientsPer100ml = entry.nutrientsPer100ml
    }

    init(preset: DrinkPreset) {
        name = preset.name
        category = preset.category
        volumeML = preset.volumeML
        alcoholPercent = preset.alcoholPercent
        hydrationPercent = preset.hydrationPercent
        nutrientsPer100ml = preset.nutrientsPer100ml
        isFavourite = preset.isFavourite
    }

    var automaticHydrationPercent: Double {
        DrinkMath.defaultHydrationPercent(category: category, alcoholPercent: effectiveAlcoholPercent)
    }

    var effectiveHydrationPercent: Double {
        hydrationPercent ?? automaticHydrationPercent
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Alcohol only applies to alcoholic categories.
    private var effectiveAlcoholPercent: Double? {
        category.isAlcoholic ? alcoholPercent : nil
    }

    func apply(to entry: DrinkEntry) {
        entry.timestamp = timestamp
        entry.name = trimmedName
        entry.category = category
        entry.volumeML = volumeML
        entry.alcoholPercent = effectiveAlcoholPercent
        entry.hydrationPercent = hydrationPercent
        entry.nutrientsPer100ml = nutrientsPer100ml
        entry.modifiedAt = .now  // restarts the Apple Health write delay
    }

    func apply(to preset: DrinkPreset) {
        preset.name = trimmedName
        preset.category = category
        preset.volumeML = volumeML
        preset.alcoholPercent = effectiveAlcoholPercent
        preset.hydrationPercent = hydrationPercent
        preset.nutrientsPer100ml = nutrientsPer100ml
        preset.isFavourite = isFavourite
    }

    func makeEntry() -> DrinkEntry {
        DrinkEntry(
            timestamp: timestamp,
            name: trimmedName,
            category: category,
            volumeML: volumeML,
            alcoholPercent: effectiveAlcoholPercent,
            hydrationPercent: hydrationPercent,
            nutrientsPer100ml: nutrientsPer100ml,
            source: .manual
        )
    }

    func makePreset(sortOrder: Int) -> DrinkPreset {
        DrinkPreset(
            name: trimmedName,
            category: category,
            volumeML: volumeML,
            alcoholPercent: effectiveAlcoholPercent,
            hydrationPercent: hydrationPercent,
            nutrientsPer100ml: nutrientsPer100ml,
            isFavourite: isFavourite,
            sortOrder: sortOrder
        )
    }
}
