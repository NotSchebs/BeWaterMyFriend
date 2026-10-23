import Foundation

/// Fixed list of drink types. Used for grouping in dashboards and for deciding
/// what counts toward the daily water goal. The free-text `name` on an entry
/// is what the user sees ("Rivella Rot"); the category is what the app groups by.
nonisolated enum DrinkCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case water
    case sparklingWater
    case tea
    case coffee
    case juice
    case softDrink
    case energyDrink
    case milk
    case sportsDrink
    /// Powder mixed into water (a scoop of electrolytes).
    case electrolytes
    /// Powder mixed into water or milk.
    case proteinShake
    case beer
    case wine
    case spirits
    case cocktail
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .water: "Water"
        case .sparklingWater: "Sparkling water"
        case .tea: "Tea"
        case .coffee: "Coffee"
        case .juice: "Juice"
        case .softDrink: "Soft drink"
        case .energyDrink: "Energy drink"
        case .milk: "Milk"
        case .sportsDrink: "Sports drink"
        case .electrolytes: "Electrolytes"
        case .proteinShake: "Protein shake"
        case .beer: "Beer"
        case .wine: "Wine"
        case .spirits: "Spirits"
        case .cocktail: "Cocktail"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .water, .sparklingWater: "drop.fill"
        case .tea: "leaf.fill"
        case .coffee: "cup.and.saucer.fill"
        case .juice: "carrot.fill"
        case .softDrink, .energyDrink, .sportsDrink: "takeoutbag.and.cup.and.straw.fill"
        case .milk: "waterbottle.fill"
        case .electrolytes: "bolt.fill"
        case .proteinShake: "dumbbell.fill"
        case .beer: "mug.fill"
        case .wine, .cocktail: "wineglass.fill"
        case .spirits: "flame.fill"
        case .other: "circle.dotted"
        }
    }

    /// Made from a scoop of powder: nutrients are per 100 g of powder.
    var isPowderMix: Bool {
        self == .electrolytes || self == .proteinShake
    }

    /// Typical scoop and liquid, used as defaults.
    var typicalPowderGrams: Double { self == .proteinShake ? 30 : 8 }
    var typicalLiquidML: Double { self == .proteinShake ? 300 : 500 }

    var isAlcoholic: Bool {
        switch self {
        case .beer, .wine, .spirits, .cocktail: true
        default: false
        }
    }
}

/// Where a logged entry came from. Every drink ends up as a normal entry.
nonisolated enum EntrySource: String, Codable, Sendable {
    case manual
    case preset
    case scan
}
