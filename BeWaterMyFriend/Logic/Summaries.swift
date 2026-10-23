import Foundation

/// Totals for one logical day.
struct DaySummary: Identifiable, Equatable {
    /// Midnight of the calendar date naming the logical day.
    let day: Date
    var entryCount = 0
    /// Fluid that counts toward the goal (each drink's hydration percentage applied).
    var goalFluidML = 0.0
    /// All fluid, including alcoholic drinks.
    var totalFluidML = 0.0
    var caffeineMg = 0.0
    var alcoholGrams = 0.0
    /// Sum of known nutrient amounts. A nutrient is missing when no drink had data for it.
    var nutrientTotals: [Nutrient: Double] = [:]

    var id: Date { day }

    var standardDrinks: Double { DrinkMath.standardDrinks(alcoholGrams: alcoholGrams) }

    func progress(goalML: Double) -> Double {
        guard goalML > 0 else { return 0 }
        return goalFluidML / goalML
    }

    func goalReached(goalML: Double) -> Bool {
        goalML > 0 && goalFluidML >= goalML
    }

    mutating func add(_ entry: DrinkEntry) {
        entryCount += 1
        totalFluidML += entry.volumeML
        goalFluidML += entry.hydrationML
        alcoholGrams += entry.alcoholGrams
        let nutrients = entry.nutrientsPer100ml  // decode once, not per nutrient
        for nutrient in Nutrient.allCases {
            if let amount = DrinkMath.scale(nutrients[nutrient], toVolumeML: entry.nutrientBase) {
                nutrientTotals[nutrient, default: 0] += amount
            }
        }
        caffeineMg += DrinkMath.scale(nutrients.caffeineMg, toVolumeML: entry.nutrientBase) ?? 0
    }
}

/// Totals for one calendar month, built from the logical days in it.
struct MonthSummary: Identifiable, Equatable {
    /// First day of the month, 00:00.
    let month: Date
    /// Days with at least one entry. Days without entries are "no data", not zero.
    var loggedDays = 0
    var daysGoalReached = 0
    var goalFluidML = 0.0
    var totalFluidML = 0.0
    var caffeineMg = 0.0
    var alcoholGrams = 0.0

    var id: Date { month }

    /// Average goal fluid per day that has entries.
    var averageGoalFluidPerLoggedDay: Double {
        loggedDays > 0 ? goalFluidML / Double(loggedDays) : 0
    }
}

enum Summaries {
    /// Summary of one logical day. Returns a zero summary when there are no entries.
    static func summary(forLogicalDay day: Date, entries: [DrinkEntry], boundary: DayBoundary) -> DaySummary {
        let interval = boundary.interval(forLogicalDay: day)
        var summary = DaySummary(day: boundary.calendar.startOfDay(for: day))
        for entry in entries where interval.start <= entry.timestamp && entry.timestamp < interval.end {
            summary.add(entry)
        }
        return summary
    }

    /// One summary per logical day that has entries, newest day first.
    static func daily(entries: [DrinkEntry], boundary: DayBoundary) -> [DaySummary] {
        var byDay: [Date: DaySummary] = [:]
        for entry in entries {
            let day = boundary.logicalDay(for: entry.timestamp)
            byDay[day, default: DaySummary(day: day)].add(entry)
        }
        return byDay.values.sorted { $0.day > $1.day }
    }

    /// One summary per month that has logged days, newest month first.
    static func monthly(days: [DaySummary], goalML: Double, calendar: Calendar) -> [MonthSummary] {
        var byMonth: [Date: MonthSummary] = [:]
        for day in days {
            let comps = calendar.dateComponents([.year, .month], from: day.day)
            let month = calendar.date(from: comps)!
            var summary = byMonth[month] ?? MonthSummary(month: month)
            summary.loggedDays += 1
            if day.goalReached(goalML: goalML) { summary.daysGoalReached += 1 }
            summary.goalFluidML += day.goalFluidML
            summary.totalFluidML += day.totalFluidML
            summary.caffeineMg += day.caffeineMg
            summary.alcoholGrams += day.alcoholGrams
            byMonth[month] = summary
        }
        return byMonth.values.sorted { $0.month > $1.month }
    }
}
