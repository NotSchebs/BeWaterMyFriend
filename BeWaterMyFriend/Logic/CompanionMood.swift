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
    // Mood rules ("what's in your body", decided 27 Oct). Each substance counts
    // on its own and fades with time; a glass of water never cancels anything.
    static let drunkWindow: TimeInterval = 3 * 3600
    static let drunkStandardDrinks = 3.0
    static let tipsyWindow: TimeInterval = 2 * 3600
    static let tipsyStandardDrinks = 1.0
    static let caffeineWindow: TimeInterval = 3 * 3600
    static let hyperCaffeineMg = 60.0
    static let powderWindow: TimeInterval = 3600

    /// Mood plus why, and until when (shown under the drop).
    struct MoodState: Equatable {
        var mood: CompanionMood
        /// e.g. "95 mg caffeine in the last 3 h"; nil when calm.
        var reason: String?
        /// When this mood ends if nothing else is drunk.
        var until: Date?
    }

    /// Priority: drunk, tipsy, hyper, strong, charged, calm.
    static func moodState(entries: [DrinkEntry], now: Date) -> MoodState {
        let past = entries.filter { $0.timestamp <= now }
        func within(_ window: TimeInterval) -> [DrinkEntry] {
            past.filter { now.timeIntervalSince($0.timestamp) < window }
        }

        let drunkDrinks = within(drunkWindow).map { ($0.timestamp, DrinkMath.standardDrinks(alcoholGrams: $0.alcoholGrams)) }
        let drunkTotal = drunkDrinks.reduce(0) { $0 + $1.1 }
        if drunkTotal >= drunkStandardDrinks {
            return MoodState(mood: .drunk, reason: "\(Format.standardDrinks(drunkTotal)) std. drinks in the last 3 h",
                             until: endTime(drunkDrinks, threshold: drunkStandardDrinks, window: drunkWindow))
        }
        let tipsyDrinks = within(tipsyWindow).map { ($0.timestamp, DrinkMath.standardDrinks(alcoholGrams: $0.alcoholGrams)) }
        let tipsyTotal = tipsyDrinks.reduce(0) { $0 + $1.1 }
        if tipsyTotal >= tipsyStandardDrinks {
            return MoodState(mood: .tipsy, reason: "\(Format.standardDrinks(tipsyTotal)) std. drinks in the last 2 h",
                             until: endTime(tipsyDrinks, threshold: tipsyStandardDrinks, window: tipsyWindow))
        }
        let caffeine = within(caffeineWindow).map { ($0.timestamp, $0.caffeineMg) }
        let caffeineTotal = caffeine.reduce(0) { $0 + $1.1 }
        if caffeineTotal >= hyperCaffeineMg {
            return MoodState(mood: .hyper, reason: "\(Format.mg(caffeineTotal)) caffeine in the last 3 h",
                             until: endTime(caffeine, threshold: hyperCaffeineMg, window: caffeineWindow))
        }
        let powders = within(powderWindow)
        if let protein = powders.filter({ $0.category == .proteinShake || $0.category == .proteinDrink }).map(\.timestamp).max() {
            return MoodState(mood: .strong, reason: "Protein in the last hour", until: protein.addingTimeInterval(powderWindow))
        }
        if let electro = powders.filter({ $0.category == .electrolytes }).map(\.timestamp).max() {
            return MoodState(mood: .charged, reason: "Electrolytes in the last hour", until: electro.addingTimeInterval(powderWindow))
        }
        return MoodState(mood: .calm)
    }

    static func mood(entries: [DrinkEntry], now: Date) -> CompanionMood {
        moodState(entries: entries, now: now).mood
    }

    /// When the amounts still inside the window drop below the threshold, as the
    /// oldest drinks leave the window one by one.
    static func endTime(_ items: [(Date, Double)], threshold: Double, window: TimeInterval) -> Date? {
        var remaining = items.reduce(0) { $0 + $1.1 }
        for (time, amount) in items.sorted(by: { $0.0 < $1.0 }) {
            remaining -= amount
            if remaining < threshold { return time.addingTimeInterval(window) }
        }
        return nil
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

    /// How the drop looks for a whole past day (History): the day's "headline".
    static func dayMood(_ day: DaySummary) -> CompanionMood {
        if day.standardDrinks >= drunkStandardDrinks { return .drunk }
        if day.standardDrinks >= tipsyStandardDrinks { return .tipsy }
        if day.caffeineMg >= 200 { return .hyper }
        return .calm
    }

    /// The drop's one or two sentences about a past day.
    static func dayCaption(_ day: DaySummary, goalML: Double) -> String {
        var parts: [String] = []
        if day.goalReached(goalML: goalML) {
            parts.append("Goal reached with \(Format.ml(day.goalFluidML)). Well trained!")
        } else {
            parts.append("\(Format.ml(max(goalML - day.goalFluidML, 0))) short of the goal.")
        }
        if day.standardDrinks >= drunkStandardDrinks {
            parts.append("A party day: \(Format.standardDrinks(day.standardDrinks)) std. drinks.")
        } else if day.caffeineMg >= 200 {
            parts.append("Lots of caffeine: \(Format.mg(day.caffeineMg)).")
        }
        return parts.joined(separator: " ")
    }
}
