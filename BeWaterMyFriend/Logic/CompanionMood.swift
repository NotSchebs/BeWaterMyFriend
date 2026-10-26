import Foundation

/// How the ninja drop behaves, based on what was drunk recently. Just for fun:
/// the thresholds are playful, not health advice.
nonisolated enum CompanionMood: Equatable, Sendable {
    case calm
    /// Caffeine recently: jittery, wide eyes.
    case hyper
    /// Last drink was alcoholic: sways, sleepy eyes, rosy cheeks.
    case tipsy
    /// Too much alcohol recently (see `heavyAlcoholStandardDrinks`): sways a lot, dizzy eyes.
    case drunk
    /// Protein shake recently: flexes little arms.
    case strong
    /// Electrolytes recently: sparks around it.
    case charged
}

/// Colour group of a drink inside the drop and the ring.
nonisolated enum DrinkTint: Hashable, Sendable {
    case water, coffee, tea, juice, soda, energy, milk, electrolytes, beer, wine, spirits

    /// Name shown in the colour legend.
    var displayName: String {
        switch self {
        case .water: "Water"
        case .coffee: "Coffee"
        case .tea: "Tea"
        case .juice: "Juice"
        case .soda: "Soft drinks"
        case .energy: "Energy drinks"
        case .milk: "Milk & protein"
        case .electrolytes: "Electrolytes & sports"
        case .beer: "Beer"
        case .wine: "Wine"
        case .spirits: "Spirits & cocktails"
        }
    }
}

/// Total for one colour group, for the legend.
nonisolated struct TintTotal: Equatable, Sendable {
    var tint: DrinkTint
    /// Millilitres counting toward the goal.
    var ml: Double
}

extension DrinkCategory {
    var tint: DrinkTint {
        switch self {
        case .water, .sparklingWater, .other: .water
        case .coffee: .coffee
        case .tea: .tea
        case .juice: .juice
        case .softDrink: .soda
        case .energyDrink: .energy
        case .milk, .proteinShake, .proteinDrink: .milk
        case .electrolytes, .sportsDrink: .electrolytes
        case .beer: .beer
        case .wine: .wine
        case .spirits, .cocktail: .spirits
        }
    }
}

/// One coloured band of the drop's fill, as a share of the daily goal.
nonisolated struct FillLayer: Equatable, Sendable {
    var tint: DrinkTint
    var fraction: Double
}

enum CompanionLogic {
    /// How long a drink keeps affecting the mood.
    static let caffeineWindow: TimeInterval = 3 * 3600
    static let alcoholWindow: TimeInterval = 3 * 3600
    static let powderWindow: TimeInterval = 2 * 3600
    /// Standard drinks within `alcoholWindow` that make the drop properly drunk.
    static let heavyAlcoholStandardDrinks = 3.0

    /// The mood follows the most recent drink while it's still recent, except
    /// that too much alcohol always wins ("extra drunk").
    static func mood(entries: [DrinkEntry], now: Date) -> CompanionMood {
        let past = entries.filter { $0.timestamp <= now }
        let recentAlcohol = past
            .filter { now.timeIntervalSince($0.timestamp) <= alcoholWindow }
            .reduce(0) { $0 + $1.alcoholGrams }
        if DrinkMath.standardDrinks(alcoholGrams: recentAlcohol) >= heavyAlcoholStandardDrinks { return .drunk }

        guard let last = past.max(by: { $0.timestamp < $1.timestamp }) else { return .calm }
        let age = now.timeIntervalSince(last.timestamp)
        if last.alcoholGrams > 0 && age <= alcoholWindow { return .tipsy }
        if last.caffeineMg > 0 && age <= caffeineWindow { return .hyper }
        if (last.category == .proteinShake || last.category == .proteinDrink) && age <= powderWindow { return .strong }
        if last.category == .electrolytes && age <= powderWindow { return .charged }
        return .calm
    }

    /// Jittering is fun for a moment, not all the time: 5 seconds, twice a minute.
    static func isJitterBurst(at date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate.rounded(.down)) % 30 < 5
    }

    /// Goal millilitres per colour group, each group once, in the order the
    /// group was first drunk today.
    static func tintTotals(entries: [DrinkEntry]) -> [TintTotal] {
        var totals: [TintTotal] = []
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) where entry.hydrationML > 0 {
            if let index = totals.firstIndex(where: { $0.tint == entry.category.tint }) {
                totals[index].ml += entry.hydrationML
            } else {
                totals.append(TintTotal(tint: entry.category.tint, ml: entry.hydrationML))
            }
        }
        return totals
    }

    /// One band per colour group (grouped, so it's easy to read), bottom to top.
    /// Past 100 % the bands are scaled down together, so every drink stays visible.
    static func fillLayers(entries: [DrinkEntry], goalML: Double) -> [FillLayer] {
        guard goalML > 0 else { return [] }
        var layers = tintTotals(entries: entries).map { FillLayer(tint: $0.tint, fraction: $0.ml / goalML) }
        let total = layers.reduce(0) { $0 + $1.fraction }
        if total > 1 {
            layers = layers.map { FillLayer(tint: $0.tint, fraction: $0.fraction / total) }
        }
        return layers
    }
}
