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
        dayMood(standardDrinks: day.standardDrinks, caffeineMg: day.caffeineMg)
    }

    static func dayMood(standardDrinks: Double, caffeineMg: Double) -> CompanionMood {
        if standardDrinks >= drunkStandardDrinks { return .drunk }
        if standardDrinks >= tipsyStandardDrinks { return .tipsy }
        if caffeineMg >= 200 { return .hyper }
        return .calm
    }

    /// The drop's one or two sentences about a past day.
    static func dayCaption(_ day: DaySummary, goalML: Double, seed: Int = 0) -> String {
        var parts: [String] = []
        let amount = Format.ml(day.goalFluidML)
        if day.goalReached(goalML: goalML) {
            parts.append(CompanionLines.pick(["Goal reached with \(amount). Well trained!",
                                              "\(amount), goal reached. A good day in the dojo!",
                                              "We made it: \(amount). Osu!"], seed: seed))
        } else {
            let missing = Format.ml(max(goalML - day.goalFluidML, 0))
            parts.append(CompanionLines.pick(["\(missing) short of the goal.",
                                              "Only \(missing) missing to the goal.",
                                              "\(missing) away from the goal. Next time!"], seed: seed))
        }
        if day.standardDrinks >= drunkStandardDrinks {
            let std = Format.standardDrinks(day.standardDrinks)
            parts.append(CompanionLines.pick(["A party day: \(std) std. drinks.", "\(std) std. drinks… my head still spins."], seed: seed))
        } else if day.caffeineMg >= 200 {
            let mg = Format.mg(day.caffeineMg)
            parts.append(CompanionLines.pick(["Lots of caffeine: \(mg).", "\(mg) caffeine. I was buzzing!"], seed: seed))
        }
        return parts.joined(separator: " ")
    }

    /// One step of the day replay: how the drop looked right after a drink.
    struct ReplayStep: Equatable {
        var time: Date
        var name: String
        var progress: Double
        var layers: [FillLayer]
        var mood: CompanionMood
        /// The mood is different from the step before (or from calm, for the first).
        var moodChanged: Bool
    }

    /// The day drink by drink, oldest first. Each step uses the same rules as the
    /// Today screen at the moment of that drink, so the replay shows exactly what
    /// the drop did that day.
    static func replay(entries: [DrinkEntry], goalML: Double) -> [ReplayStep] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var steps: [ReplayStep] = []
        var previous = CompanionMood.calm
        var fluid = 0.0
        for (i, entry) in sorted.enumerated() {
            let soFar = Array(sorted[...i])
            fluid += entry.hydrationML
            let mood = mood(entries: soFar, now: entry.timestamp)
            steps.append(ReplayStep(time: entry.timestamp, name: entry.name,
                                    progress: goalML > 0 ? fluid / goalML : 0,
                                    layers: fillLayers(entries: soFar, goalML: goalML),
                                    mood: mood, moodChanged: mood != previous))
            previous = mood
        }
        return steps
    }

    /// The day with the most fluid toward the goal (the earliest on a tie); nil
    /// when no day has any.
    static func bestDay(in days: [DaySummary]) -> DaySummary? {
        days.filter { $0.goalFluidML > 0 }
            .sorted { $0.day < $1.day }
            .max { $0.goalFluidML < $1.goalFluidML }
    }

    /// The drop's face for a colour group (Stats donut): what that drink does.
    static func mood(for tint: DrinkTint) -> CompanionMood {
        switch tint {
        case .coffee, .energy: .hyper
        case .beer, .wine, .spirits: .tipsy
        case .milk: .strong
        case .electrolytes: .charged
        case .water, .tea, .juice, .soda: .calm
        }
    }
}
