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

    // MARK: Today

    /// What the drop says on the Today screen and the Large widget.
    static func todayMessage(mood: CompanionMood, progress: Double) -> String {
        switch mood {
        case .drunk: return "Whoa… the room is spinning. Water break?"
        case .tipsy: return "Feeling a bit wobbly… hic!"
        case .hyper: return "Caffeine rush! Zoom zoom!"
        case .strong: return "Protein power! Feeling strong."
        case .charged: return "Fully charged with electrolytes!"
        case .calm: break
        }
        switch progress {
        case ..<0.01: return "Your training begins. One sip at a time."
        case ..<0.5: return "Flow like water, my friend."
        case ..<1: return "More than halfway. Keep flowing."
        default: return "Goal reached. Well trained!"
        }
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
            return pick(["Nothing logged on \(dayText).",
                         "No data for \(dayText). Was I forgotten?",
                         "\(dayText) is a blank page.",
                         "\(dayText): no entries, no verdict."], seed: seed)
        }
        let amount = Format.ml(ml)
        if goalML > 0 && ml >= goalML {
            return pick(["\(dayText): \(amount). Goal reached!",
                         "\(dayText): \(amount). Well trained!",
                         "\(dayText): \(amount). That's how a ninja trains.",
                         "\(dayText): \(amount). Flowing like a river that day."], seed: seed)
        }
        let missing = Format.ml(max(goalML - ml, 0))
        return pick(["\(dayText): \(amount), \(missing) short.",
                     "\(dayText): \(amount). \(missing) to go that day.",
                     "\(dayText): \(amount). Every sip counts, \(missing) more next time.",
                     "\(dayText): \(amount). A good session, the goal was \(missing) away."], seed: seed)
    }

    static func statsCaffeine(mg: Double, dayText: String, seed: Int) -> String {
        guard mg > 0 else {
            return pick(["No caffeine on \(dayText).",
                         "\(dayText): no caffeine. A calm day.",
                         "\(dayText): no caffeine. Still as a pond.",
                         "\(dayText): zero buzz, full zen."], seed: seed)
        }
        let amount = Format.mg(mg)
        return pick(["\(dayText): \(amount) caffeine.",
                     "\(dayText): \(amount) caffeine. Buzz!",
                     "\(dayText): \(amount) caffeine. Zoom zoom!",
                     "\(dayText): \(amount) caffeine. My headband was vibrating."], seed: seed)
    }

    static func statsAlcohol(standardDrinks: Double, dayText: String, seed: Int) -> String {
        guard standardDrinks > 0 else {
            return pick(["No alcohol on \(dayText).",
                         "\(dayText): no alcohol. Clear head!",
                         "\(dayText): no alcohol. Sharp as a blade.",
                         "\(dayText): alcohol-free and steady on my feet."], seed: seed)
        }
        let amount = Format.standardDrinks(standardDrinks)
        return pick(["\(dayText): \(amount) std. drinks.",
                     "\(dayText): \(amount) std. drinks. Cheers!",
                     "\(dayText): \(amount) std. drinks. Even ninjas need a day off.",
                     "\(dayText): \(amount) std. drinks. A glass of water for the road?"], seed: seed)
    }

    /// `weekdayText` is the full name ("Saturday").
    static func statsWeekday(ml: Double, weekdayText: String, seed: Int) -> String {
        let amount = Format.ml(ml)
        return pick(["\(weekdayText)s: \(amount) on average.",
                     "A usual \(weekdayText): \(amount).",
                     "\(weekdayText)s average out at \(amount). Nice rhythm.",
                     "\(amount) is your \(weekdayText) routine."], seed: seed)
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
        let amount = Format.ml(ml)
        return pick(["\(name): \(amount), \(percent) of what you drank.",
                     "\(name): \(percent) of the donut. That's \(amount).",
                     "\(name) has a \(percent) slice: \(amount) in total.",
                     "\(percent) of your drinks: \(name). Good to know!"], seed: seed)
    }

    // MARK: Black belt

    /// In martial arts the black belt is the beginning, so the screen says so and
    /// then shows the quote the app is named after.
    static let blackBeltLine = "Black belt is just the beginning"

    static let bruceLeeQuote = "Empty your mind. Be formless, shapeless, like water. You put water into a cup, it becomes the cup. "
        + "You put water into a bottle, it becomes the bottle. You put it into a teapot, it becomes the teapot. "
        + "Now water can flow or it can crash. Be water, my friend."
}
