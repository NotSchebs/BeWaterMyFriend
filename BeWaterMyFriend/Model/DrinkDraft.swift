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
    /// Grams of powder, only used for powder categories.
    var powderGrams: Double?
    var nutrientsPer100ml = Nutrients()
    var isFavourite = false
    var source: EntrySource = .manual
    var barcode: String?
    /// For scans: also keep it as a preset so corrections are reused next time.
    var saveAsPreset = false
    /// For scans: what the database said, shown as a hint while reviewing.
    var scanNote: String?

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
        powderGrams = entry.powderGrams
        nutrientsPer100ml = entry.nutrientsPer100ml
    }

    /// Pre-filled from a scan, for the user to review before saving.
    init(scanned product: ScannedProduct) {
        name = product.name
        category = product.category
        volumeML = product.suggestedVolumeML
        powderGrams = product.powderGrams
        alcoholPercent = product.alcoholPercent
        nutrientsPer100ml = product.nutrientsPer100ml
        source = .scan
        barcode = product.barcode
        saveAsPreset = true
        var notes = ["From Open Food Facts. Check the values, especially caffeine, before saving."]
        if let package = product.packageVolumeML, package != product.suggestedVolumeML {
            notes.append("Package: \(Int(package)) ml.")
        }
        if product.powderGrams != nil {
            notes.append("Powder: values are per 100 g of powder. Set your scoop size and how much liquid you mixed it with.")
        } else if product.valuesWerePer100g {
            notes.append("Values were given per 100 g and are used as per 100 ml.")
        }
        scanNote = notes.joined(separator: " ")
    }

    /// From a saved preset with the same barcode.
    init(scannedPreset preset: DrinkPreset) {
        self.init(preset: preset)
        source = .scan
        saveAsPreset = true  // corrections made now update the saved version
        scanNote = "Your saved version of this product."
    }

    /// Unknown product: the user enters it; it's remembered for next time.
    init(unknownBarcode barcode: String) {
        name = ""
        source = .scan
        self.barcode = barcode
        saveAsPreset = true
        scanNote = "Not found in Open Food Facts. Enter it once and it will be remembered for this barcode."
    }

    init(preset: DrinkPreset) {
        name = preset.name
        category = preset.category
        volumeML = preset.volumeML
        alcoholPercent = preset.alcoholPercent
        hydrationPercent = preset.hydrationPercent
        powderGrams = preset.powderGrams
        nutrientsPer100ml = preset.nutrientsPer100ml
        isFavourite = preset.isFavourite
        barcode = preset.barcode
    }

    var automaticHydrationPercent: Double {
        DrinkMath.defaultHydrationPercent(category: category, alcoholPercent: effectiveAlcoholPercent)
    }

    var effectiveHydrationPercent: Double {
        hydrationPercent ?? automaticHydrationPercent
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Powder only applies to powder categories.
    var effectivePowderGrams: Double? {
        category.isPowderMix ? (powderGrams ?? category.typicalPowderGrams) : nil
    }

    /// What nutrient values are scaled by in the editor.
    var nutrientBase: Double { effectivePowderGrams ?? volumeML }

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
        entry.powderGrams = effectivePowderGrams
        entry.nutrientsPer100ml = nutrientsPer100ml
        entry.modifiedAt = .now  // restarts the Apple Health write delay
    }

    func apply(to preset: DrinkPreset) {
        preset.name = trimmedName
        preset.category = category
        preset.volumeML = volumeML
        preset.alcoholPercent = effectiveAlcoholPercent
        preset.hydrationPercent = hydrationPercent
        preset.powderGrams = effectivePowderGrams
        preset.nutrientsPer100ml = nutrientsPer100ml
        preset.isFavourite = isFavourite
        if let barcode { preset.barcode = barcode }
    }

    func makeEntry() -> DrinkEntry {
        DrinkEntry(
            timestamp: timestamp,
            name: trimmedName,
            category: category,
            volumeML: volumeML,
            alcoholPercent: effectiveAlcoholPercent,
            hydrationPercent: hydrationPercent,
            powderGrams: effectivePowderGrams,
            nutrientsPer100ml: nutrientsPer100ml,
            source: source,
            barcode: barcode
        )
    }

    func makePreset(sortOrder: Int) -> DrinkPreset {
        DrinkPreset(
            name: trimmedName,
            category: category,
            volumeML: volumeML,
            alcoholPercent: effectiveAlcoholPercent,
            hydrationPercent: hydrationPercent,
            powderGrams: effectivePowderGrams,
            nutrientsPer100ml: nutrientsPer100ml,
            isFavourite: isFavourite,
            sortOrder: sortOrder,
            barcode: barcode
        )
    }
}
