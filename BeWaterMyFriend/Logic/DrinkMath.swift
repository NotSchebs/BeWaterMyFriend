import Foundation

/// Pure calculation helpers. All values are estimates, not medical advice.
nonisolated enum DrinkMath {
    /// Density of ethanol in g/ml.
    static let ethanolDensity = 0.789
    /// Grams of pure alcohol in one standard drink (WHO uses 10 g; Swiss
    /// sources give 10–12 g). Only used for display.
    static let gramsPerStandardDrink = 10.0

    /// Scales a per-100 ml value to the drunk volume: 330 ml → × 3.3.
    /// Unknown (`nil`) stays unknown.
    static func scale(_ per100ml: Double?, toVolumeML volumeML: Double) -> Double? {
        guard let per100ml else { return nil }
        return per100ml * volumeML / 100
    }

    /// Inverse of `scale`: turns a total for a given volume into a per-100 ml value.
    static func per100ml(fromTotal total: Double?, volumeML: Double) -> Double? {
        guard let total, volumeML > 0 else { return nil }
        return total / volumeML * 100
    }

    /// Grams of pure alcohol: volume × ABV × ethanol density.
    static func alcoholGrams(volumeML: Double, alcoholPercent: Double?) -> Double {
        guard let alcoholPercent, alcoholPercent > 0, volumeML > 0 else { return 0 }
        return volumeML * alcoholPercent / 100 * ethanolDensity
    }

    static func standardDrinks(alcoholGrams: Double) -> Double {
        alcoholGrams / gramsPerStandardDrink
    }
}
