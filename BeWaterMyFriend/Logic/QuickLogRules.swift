import Foundation

/// Rules for the Quick log grid and for finding drinks the user already has.
enum QuickLogRules {
    /// The grid shows at most this many presets.
    static let maxItems = 12

    /// Presets shown in the grid, in the user's order, at most `maxItems`.
    static func visible(_ presets: [DrinkPreset]) -> [DrinkPreset] {
        Array(ordered(presets).filter(\.isInQuickLog).prefix(maxItems))
    }

    private static func ordered(_ presets: [DrinkPreset]) -> [DrinkPreset] {
        presets.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Drag and drop: `dragged` takes `target`'s place. Hidden presets keep their
    /// place in the Settings list, because both screens share `sortOrder`.
    static func move(_ dragged: DrinkPreset, onto target: DrinkPreset, in presets: [DrinkPreset]) {
        var list = ordered(presets)
        guard let from = list.firstIndex(where: { $0 === dragged }),
              let to = list.firstIndex(where: { $0 === target }), from != to else { return }
        list.remove(at: from)
        list.insert(dragged, at: to)
        for (index, preset) in list.enumerated() { preset.sortOrder = index }
    }

    /// For adding at the end of the Quick log.
    static func nextSortOrder(_ presets: [DrinkPreset]) -> Int {
        (presets.map(\.sortOrder).max() ?? -1) + 1
    }

    /// The preset that is exactly this drink: same barcode, or same name, type and
    /// amount. "Coffee 500 ml" is a different Quick log tile from "Coffee 250 ml".
    static func matching(_ draft: DrinkDraft, in presets: [DrinkPreset]) -> DrinkPreset? {
        if let barcode = draft.barcode, let match = presets.first(where: { $0.barcode == barcode }) {
            return match
        }
        let key = normalized(draft.name)
        return presets.first {
            normalized($0.name) == key && $0.category == draft.category && Int($0.volumeML) == Int(draft.volumeML)
        }
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

/// Starred drinks exist only for the widgets' quick-log buttons: at most three,
/// numbered ★1–★3 without gaps. The number is the widget position: ★1 is on the
/// Small widget, Medium shows ★1 to ★3. They don't affect the Quick log.
enum DrinkStars {
    static let maxStars = 3

    static func starred(_ presets: [DrinkPreset]) -> [DrinkPreset] {
        presets.filter { $0.starNumber != nil }
            .sorted { ($0.starNumber ?? 0, $0.sortOrder) < ($1.starNumber ?? 0, $1.sortOrder) }
    }

    /// The drinks a widget shows: the stars, or the first Quick log drinks if there are none.
    static func widgetDrinks(_ presets: [DrinkPreset]) -> [DrinkPreset] {
        let stars = starred(presets)
        return stars.isEmpty ? Array(QuickLogRules.visible(presets).prefix(maxStars)) : stars
    }

    /// Gives the drink the next free number. False when all three are taken.
    @discardableResult
    static func star(_ preset: DrinkPreset, in presets: [DrinkPreset]) -> Bool {
        guard preset.starNumber == nil else { return true }
        let list = starred(presets)
        guard list.count < maxStars else { return false }
        number(list + [preset])
        return true
    }

    /// Frees the number; the others move up.
    static func unstar(_ preset: DrinkPreset, in presets: [DrinkPreset]) {
        preset.starNumber = nil
        compact(presets)
    }

    /// Choosing a number: swaps with the drink that has it. A drink without a star
    /// takes over the number, and the drink that had it loses its star.
    static func assign(_ preset: DrinkPreset, number target: Int, in presets: [DrinkPreset]) {
        var list = starred(presets)
        let index = target - 1
        guard list.indices.contains(index) else { return }
        if let current = list.firstIndex(where: { $0 === preset }) {
            list.swapAt(current, index)
        } else {
            list[index].starNumber = nil
            list[index] = preset
        }
        number(list)
    }

    /// Closes gaps, e.g. after a starred drink was deleted.
    static func compact(_ presets: [DrinkPreset]) {
        number(starred(presets))
    }

    /// Once after the update: the first three old favourites get numbers, the rest
    /// lose their star. Returns true if anything changed.
    @discardableResult
    static func migrateOldFavourites(_ presets: [DrinkPreset]) -> Bool {
        let old = presets.filter(\.isFavourite).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        for preset in old {
            preset.isFavourite = false
            star(preset, in: presets)
        }
        return !old.isEmpty
    }

    private static func number(_ list: [DrinkPreset]) {
        for (index, preset) in list.enumerated() { preset.starNumber = index + 1 }
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
