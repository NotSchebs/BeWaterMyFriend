import Foundation

/// How the ninja drop behaves, based on what was drunk recently. Just for fun:
/// the thresholds are playful, not health advice.
nonisolated enum CompanionMood: Equatable, Sendable {
    case calm
    /// Caffeine recently: jittery, wide eyes.
    case hyper
    /// Alcohol recently: sways, sleepy eyes, rosy cheeks.
    case tipsy
    /// Protein shake recently: flexes little arms.
    case strong
    /// Electrolytes recently: sparks around it.
    case charged
}

/// Colour group of a drink inside the drop.
nonisolated enum DrinkTint: Equatable, Sendable {
    case water, coffee, tea, juice, soda, energy, milk, electrolytes, beer, wine, spirits
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
        case .milk, .proteinShake: .milk
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
    /// Recent-drink windows and thresholds.
    static let caffeineWindow: TimeInterval = 3 * 3600
    static let caffeineThresholdMg = 80.0
    static let alcoholWindow: TimeInterval = 3 * 3600
    static let alcoholThresholdGrams = DrinkMath.gramsPerStandardDrink
    static let powderWindow: TimeInterval = 2 * 3600

    /// Priority: tipsy, hyper, strong, charged, calm.
    static func mood(entries: [DrinkEntry], now: Date) -> CompanionMood {
        func recent(_ window: TimeInterval) -> [DrinkEntry] {
            entries.filter { $0.timestamp <= now && now.timeIntervalSince($0.timestamp) <= window }
        }
        if recent(alcoholWindow).reduce(0, { $0 + $1.alcoholGrams }) >= alcoholThresholdGrams { return .tipsy }
        if recent(caffeineWindow).reduce(0, { $0 + $1.caffeineMg }) >= caffeineThresholdMg { return .hyper }
        let powders = recent(powderWindow)
        if powders.contains(where: { $0.category == .proteinShake }) { return .strong }
        if powders.contains(where: { $0.category == .electrolytes }) { return .charged }
        return .calm
    }

    /// Bands from bottom to top in the order the drinks were had. Each drink
    /// adds its goal share; neighbours of the same colour merge. Capped at a full drop.
    static func fillLayers(entries: [DrinkEntry], goalML: Double) -> [FillLayer] {
        guard goalML > 0 else { return [] }
        var layers: [FillLayer] = []
        var total = 0.0
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let share = min(entry.hydrationML / goalML, 1 - total)
            guard share > 0 else { continue }
            total += share
            if layers.last?.tint == entry.category.tint {
                layers[layers.count - 1].fraction += share
            } else {
                layers.append(FillLayer(tint: entry.category.tint, fraction: share))
            }
        }
        return layers
    }
}
