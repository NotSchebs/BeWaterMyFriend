import Foundation

/// Rules for the Quick log grid and for finding drinks the user already has.
enum QuickLogRules {
    /// The grid shows at most this many presets.
    static let maxItems = 12

    /// Presets shown in the grid: favourites first, then the user's order, at most `maxItems`.
    static func visible(_ presets: [DrinkPreset]) -> [DrinkPreset] {
        let shown = presets.filter(\.isInQuickLog)
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return Array((shown.filter(\.isFavourite) + shown.filter { !$0.isFavourite }).prefix(maxItems))
    }

    static func isFull(_ presets: [DrinkPreset]) -> Bool {
        presets.filter(\.isInQuickLog).count >= maxItems
    }

    /// The preset this drink already belongs to: same barcode, or same name and type.
    static func existingPreset(barcode: String?, name: String, category: DrinkCategory,
                               in presets: [DrinkPreset]) -> DrinkPreset? {
        if let barcode, let match = presets.first(where: { $0.barcode == barcode }) {
            return match
        }
        let key = normalized(name)
        return presets.first { normalized($0.name) == key && $0.category == category }
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// How far back drinks can be logged or moved, so goal days and belts can't be
/// collected by back-filling old days.
nonisolated enum LogTimeLimit {
    /// Today plus this many previous days.
    static let daysBack = 2

    /// The earliest moment a drink may be logged at (start of the logical day `daysBack` days ago).
    static func earliest(now: Date, boundary: DayBoundary) -> Date {
        let today = boundary.logicalDay(for: now)
        let first = boundary.calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        return boundary.interval(forLogicalDay: first).start
    }

    /// The allowed range for the time picker. An entry that is already older keeps
    /// its own time as the lower bound (it can be edited, but not moved further back).
    static func range(now: Date, boundary: DayBoundary, existing: Date? = nil) -> ClosedRange<Date> {
        let lower = min(earliest(now: now, boundary: boundary), existing ?? .distantFuture)
        return lower...max(now, existing ?? now)
    }
}
