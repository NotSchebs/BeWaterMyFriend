import Foundation

/// When a logged drink is written to Apple Health. Waiting gives time to fix
/// mistakes before they reach Health; the sample always keeps the drink's own time.
nonisolated enum HealthWriteDelay: String, CaseIterable, Identifiable, Sendable {
    case immediately
    case oneHour
    case endOfDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .immediately: "Immediately"
        case .oneHour: "1 hour after logging"
        case .endOfDay: "At the end of the day"
        }
    }
}

/// One value to write to Health, in the app's own units (see `HealthQuantity.unit`).
nonisolated struct PlannedSample: Equatable, Sendable {
    var quantity: HealthQuantity
    var value: Double
}

/// Everything this app can write to Apple Health.
nonisolated enum HealthQuantity: Hashable, Sendable {
    /// Millilitres that count toward the goal (hydration percentage applied).
    case water
    /// Number of standard drinks.
    case alcoholicBeverages
    case nutrient(Nutrient)

    static var all: [HealthQuantity] {
        [.water, .alcoholicBeverages] + Nutrient.allCases.map { .nutrient($0) }
    }

    /// Unit of `PlannedSample.value`.
    var unit: String {
        switch self {
        case .water: "ml"
        case .alcoholicBeverages: "count"
        case .nutrient(let nutrient): nutrient.unit
        }
    }
}

enum HealthPlan {
    /// The samples for one entry. Unknown and zero values are skipped.
    static func samples(for entry: DrinkEntry) -> [PlannedSample] {
        var result: [PlannedSample] = []
        if entry.hydrationML > 0 {
            result.append(PlannedSample(quantity: .water, value: entry.hydrationML))
        }
        let standardDrinks = DrinkMath.standardDrinks(alcoholGrams: entry.alcoholGrams)
        if standardDrinks > 0 {
            result.append(PlannedSample(quantity: .alcoholicBeverages, value: standardDrinks))
        }
        let nutrients = entry.nutrientsPer100ml
        for nutrient in Nutrient.allCases {
            if let amount = DrinkMath.scale(nutrients[nutrient], toVolumeML: entry.nutrientBase), amount > 0 {
                result.append(PlannedSample(quantity: .nutrient(nutrient), value: amount))
            }
        }
        return result
    }

    /// The earliest moment the current version of an entry may be written.
    /// Every edit restarts the waiting time.
    static func dueDate(timestamp: Date, modifiedAt: Date?, delay: HealthWriteDelay, boundary: DayBoundary) -> Date {
        let changed = modifiedAt ?? timestamp
        switch delay {
        case .immediately:
            return changed
        case .oneHour:
            return changed.addingTimeInterval(3600)
        case .endOfDay:
            let dayEnd = boundary.interval(forLogicalDay: boundary.logicalDay(for: timestamp)).end
            return max(dayEnd, changed)
        }
    }

    static func isDue(_ entry: DrinkEntry, delay: HealthWriteDelay, boundary: DayBoundary, now: Date) -> Bool {
        entry.needsHealthWrite
            && dueDate(timestamp: entry.timestamp, modifiedAt: entry.modifiedAt, delay: delay, boundary: boundary) <= now
    }
}
