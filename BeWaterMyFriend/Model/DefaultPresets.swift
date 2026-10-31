import Foundation
import SwiftData

/// Presets created on first launch. Caffeine and alcohol values are typical
/// estimates, not measurements; the user can edit or delete every preset.
enum DefaultPresets {
    static func make() -> [DrinkPreset] {
        func caffeine(_ mgPer100ml: Double) -> Nutrients {
            var n = Nutrients()
            n.caffeineMg = mgPer100ml
            return n
        }

        return [
            DrinkPreset(name: "Glass of water", category: .water, volumeML: 250, starNumber: 1, sortOrder: 0),
            DrinkPreset(name: "Bottle of water", category: .water, volumeML: 500, starNumber: 2, sortOrder: 1),
            // ~63 mg per 30 ml shot
            DrinkPreset(name: "Espresso", category: .coffee, volumeML: 30, nutrientsPer100ml: caffeine(210), starNumber: 3, sortOrder: 2),
            // ~95 mg per 240 ml cup
            DrinkPreset(name: "Coffee", category: .coffee, volumeML: 250, nutrientsPer100ml: caffeine(40), sortOrder: 3),
            // ~30 mg per 250 ml cup
            DrinkPreset(name: "Black tea", category: .tea, volumeML: 250, nutrientsPer100ml: caffeine(12), sortOrder: 4),
            DrinkPreset(name: "Herbal tea", category: .tea, volumeML: 250, sortOrder: 5),
            DrinkPreset(name: "Beer", category: .beer, volumeML: 330, alcoholPercent: 5, sortOrder: 6),
            DrinkPreset(name: "Glass of wine", category: .wine, volumeML: 150, alcoholPercent: 12, sortOrder: 7),
        ]
    }

    /// Inserts the defaults on first launch only, so presets the user deleted
    /// don't come back.
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: SettingsKey.didSeedPresets) else { return }
        let count = (try? context.fetchCount(FetchDescriptor<DrinkPreset>())) ?? 0
        if count == 0 {
            make().forEach { context.insert($0) }
            try? context.save()
        }
        defaults.set(true, forKey: SettingsKey.didSeedPresets)
    }
}
