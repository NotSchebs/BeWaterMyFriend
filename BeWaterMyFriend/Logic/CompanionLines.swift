import Foundation

/// The ninja drop's wording. Most messages have a few variants so the drop
/// doesn't say the same sentence every time; `seed` picks one. Callers pass a
/// seed that stays the same while the screen is open (e.g. the day number) and
/// changes with a tap, so the text never flickers on its own.
/// Variant 0 is always the plain one (used in tests).
enum CompanionLines {
    static func pick(_ variants: [String], seed: Int) -> String {
        let n = variants.count
        return variants[((seed % n) + n) % n]
    }

    /// A seed that changes once per day.
    static func daySeed(_ date: Date, calendar: Calendar) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    // MARK: Day replay

    static func replayStart(seed: Int) -> String {
        pick(["Back to the start of the day…", "Rewinding… empty again!", "Let's see how today went."], seed: seed)
    }

    /// One line per drink while replaying, e.g. "Coffee – now I'm hyper!".
    static func replayLine(name: String, mood: CompanionMood, moodChanged: Bool) -> String {
        guard moodChanged else { return name }
        switch mood {
        case .calm: return "\(name) – calm again."
        case .hyper: return "\(name) – now I'm hyper!"
        case .tipsy: return "\(name) – getting tipsy…"
        case .drunk: return "\(name) – whoa, drunk!"
        case .strong: return "\(name) – feeling strong!"
        case .charged: return "\(name) – charged up!"
        }
    }

    // MARK: History

    static func bestDay(ml: Double, dayText: String, monthText: String, seed: Int) -> String {
        let amount = Format.ml(ml)
        return pick(["Best day of the month: \(amount) on \(dayText).",
                     "My favourite day in \(monthText): \(amount)!",
                     "\(amount) on \(dayText). The best one this month."], seed: seed)
    }

    // MARK: Stats taps

    static func statsDay(ml: Double?, goalML: Double, dayText: String, seed: Int) -> String {
        guard let ml else {
            return pick(["Nothing logged on \(dayText).", "No data for \(dayText). Was I forgotten?"], seed: seed)
        }
        if goalML > 0 && ml >= goalML {
            return pick(["\(dayText): \(Format.ml(ml)). Goal reached!", "\(dayText): \(Format.ml(ml)). Well trained!"], seed: seed)
        }
        let missing = Format.ml(max(goalML - ml, 0))
        return pick(["\(dayText): \(Format.ml(ml)), \(missing) short.", "\(dayText): \(Format.ml(ml)). \(missing) to go that day."], seed: seed)
    }

    static func statsCaffeine(mg: Double, dayText: String, seed: Int) -> String {
        guard mg > 0 else { return pick(["No caffeine on \(dayText).", "\(dayText): no caffeine. A calm day."], seed: seed) }
        return pick(["\(dayText): \(Format.mg(mg)) caffeine.", "\(dayText): \(Format.mg(mg)) caffeine. Buzz!"], seed: seed)
    }

    static func statsAlcohol(standardDrinks: Double, dayText: String, seed: Int) -> String {
        guard standardDrinks > 0 else { return pick(["No alcohol on \(dayText).", "\(dayText): no alcohol. Clear head!"], seed: seed) }
        return pick(["\(dayText): \(Format.standardDrinks(standardDrinks)) std. drinks.",
                     "\(dayText): \(Format.standardDrinks(standardDrinks)) std. drinks. Cheers!"], seed: seed)
    }

    /// `weekdayText` is the full name ("Saturday").
    static func statsWeekday(ml: Double, weekdayText: String, seed: Int) -> String {
        pick(["\(weekdayText)s: \(Format.ml(ml)) on average.", "On \(weekdayText)s I usually get \(Format.ml(ml))."], seed: seed)
    }

    // MARK: Add drink

    static func addIdle(seed: Int) -> String {
        pick(["What are we drinking?", "Thirsty? Search, scan or make a new one."], seed: seed)
    }

    static func addSuggestion(name: String, ml: Double, seed: Int) -> String {
        pick(["Around this time you usually have \(name) (\(Format.ml(ml))). Tap me to log it.",
              "It's \(name) time, isn't it? Tap me and it's ready."], seed: seed)
    }

    static func addSearching(_ query: String) -> String { "Looking for \"\(query)\"…" }

    static func addNotFound(_ query: String) -> String {
        "Never had \"\(query)\" before. Scan it or make a new drink?"
    }

    // MARK: Stats donut

    static func statsDrinkType(name: String, ml: Double, share: Double, seed: Int) -> String {
        let percent = Format.percent(share)
        return pick(["\(name): \(Format.ml(ml)), \(percent) of what you drank.",
                     "\(percent) \(name). That's \(Format.ml(ml)) in me!"], seed: seed)
    }
}
