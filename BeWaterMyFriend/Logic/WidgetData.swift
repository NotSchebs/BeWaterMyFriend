import Foundation

// What the app and the widgets share, through an App Group folder. The widgets
// never touch the drink database, so the user's data stays where it always was:
// - the app leaves a small snapshot of today (`WidgetSnapshot`),
// - a widget button only leaves a note (`pending`), which the app turns into a
//   real drink when it opens. Until then the widget simply counts it too.

/// A drink as the widgets know it: a star to log, or something drunk recently.
nonisolated struct WidgetDrink: Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var categoryRaw: String
    var volumeML: Double
    var alcoholPercent: Double?
    var hydrationPercent: Double?
    var powderGrams: Double?
    var nutrients: Nutrients
    var barcode: String?
    var timestamp: Date
    /// Set when the user starred it; nil for the fallback drinks without stars.
    var starNumber: Int?

    var category: DrinkCategory { DrinkCategory(rawValue: categoryRaw) ?? .other }
}

extension WidgetDrink {
    init(entry: DrinkEntry) {
        self.init(name: entry.name, categoryRaw: entry.categoryRaw, volumeML: entry.volumeML,
                  alcoholPercent: entry.alcoholPercent, hydrationPercent: entry.hydrationPercent,
                  powderGrams: entry.powderGrams, nutrients: entry.nutrientsPer100ml,
                  barcode: entry.barcode, timestamp: entry.timestamp)
    }

    init(preset: DrinkPreset, now: Date) {
        self.init(name: preset.name, categoryRaw: preset.categoryRaw, volumeML: preset.volumeML,
                  alcoholPercent: preset.alcoholPercent, hydrationPercent: preset.hydrationPercent,
                  powderGrams: preset.powderGrams, nutrients: preset.nutrientsPer100ml,
                  barcode: preset.barcode, timestamp: now, starNumber: preset.starNumber)
    }

    /// A real drink, like tapping the preset in the Quick log.
    func makeEntry() -> DrinkEntry {
        DrinkEntry(timestamp: timestamp, name: name, category: category, volumeML: volumeML,
                   alcoholPercent: alcoholPercent, hydrationPercent: hydrationPercent, powderGrams: powderGrams,
                   nutrientsPer100ml: nutrients, source: barcode == nil ? .preset : .scan, barcode: barcode)
    }
}

/// What the app last told the widgets.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var goalML: Double
    var dayEndMinutes: Int
    var beltRaw: Int
    var prestige: Int
    var companionEnabled: Bool
    /// Today's drinks, plus earlier ones that can still affect the drop's mood.
    var recent: [WidgetDrink]
    /// Up to three: the starred drinks by number, or the first Quick log drinks.
    var quickDrinks: [WidgetDrink]
}

/// The shared folder.
nonisolated enum WidgetStore {
    static let groupID = "group.com.notschebs.BeWaterMyFriend"
    private static let snapshotKey = "widgetSnapshot"
    private static let pendingKey = "widgetPendingDrinks"

    static var shared: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func snapshot(in defaults: UserDefaults = shared) -> WidgetSnapshot? {
        defaults.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }

    static func save(_ snapshot: WidgetSnapshot, in defaults: UserDefaults = shared) {
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: snapshotKey)
    }

    static func pending(in defaults: UserDefaults = shared) -> [WidgetDrink] {
        defaults.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode([WidgetDrink].self, from: $0) } ?? []
    }

    static func addPending(_ drink: WidgetDrink, in defaults: UserDefaults = shared) {
        setPending(pending(in: defaults) + [drink], in: defaults)
    }

    /// Only the given drinks: one logged in the meantime stays.
    static func removePending(ids: Set<UUID>, in defaults: UserDefaults = shared) {
        setPending(pending(in: defaults).filter { !ids.contains($0.id) }, in: defaults)
    }

    private static func setPending(_ drinks: [WidgetDrink], in defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(drinks), forKey: pendingKey)
    }
}

/// What a widget shows at one moment, worked out with the same rules as the
/// Today screen (pure and tested).
nonisolated struct WidgetState: Sendable {
    var ml: Double
    var goalML: Double
    var layers: [FillLayer]
    var totals: [TintTotal]
    var mood: CompanionMood
    var message: String
    var caffeineMg: Double
    var standardDrinks: Double
    var totalFluidML: Double
    var belt: Belt
    var prestige: Int
    var showsDrop: Bool
    var quickDrinks: [WidgetDrink]
    /// When this picture goes out of date: the mood fades or a new day starts.
    var nextChange: Date?

    var progress: Double { goalML > 0 ? ml / goalML : 0 }

    /// Before the app has told the widgets anything.
    static let empty = WidgetState(ml: 0, goalML: 2000, layers: [], totals: [], mood: .calm,
                                   message: "Open the app once to start.", caffeineMg: 0, standardDrinks: 0,
                                   totalFluidML: 0, belt: .white, prestige: 0, showsDrop: true, quickDrinks: [],
                                   nextChange: nil)
}

extension WidgetState {
    static func make(snapshot: WidgetSnapshot?, pending: [WidgetDrink], now: Date,
                     calendar: Calendar = .current) -> WidgetState {
        guard let snapshot else { return .empty }
        let boundary = DayBoundary(dayEndMinutes: snapshot.dayEndMinutes, calendar: calendar)
        let entries = (snapshot.recent + pending).map { $0.makeEntry() }
        let today = boundary.logicalDay(for: now)
        let interval = boundary.interval(forLogicalDay: today)
        let todays = entries.filter { interval.start <= $0.timestamp && $0.timestamp < interval.end }
        let summary = Summaries.summary(forLogicalDay: today, entries: todays, boundary: boundary)
        let moodState = CompanionLogic.moodState(entries: entries, now: now)
        let progress = summary.progress(goalML: snapshot.goalML)
        let changes = [moodState.until, interval.end].compactMap { $0 }.filter { $0 > now }
        return WidgetState(ml: summary.goalFluidML, goalML: snapshot.goalML,
                           layers: CompanionLogic.fillLayers(entries: todays, goalML: snapshot.goalML),
                           totals: CompanionLogic.tintTotals(entries: todays),
                           mood: moodState.mood,
                           message: CompanionLines.todayMessage(mood: moodState.mood, progress: progress),
                           caffeineMg: summary.caffeineMg, standardDrinks: summary.standardDrinks,
                           totalFluidML: summary.totalFluidML,
                           belt: Belt(rawValue: snapshot.beltRaw) ?? .white, prestige: snapshot.prestige,
                           showsDrop: snapshot.companionEnabled, quickDrinks: snapshot.quickDrinks,
                           nextChange: changes.min())
    }
}
