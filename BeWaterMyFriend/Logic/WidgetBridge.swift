import Foundation
import SwiftData
import WidgetKit

/// The app's side of the widgets: tells them today's numbers, and collects the
/// drinks logged from them. See `WidgetData`.
enum WidgetBridge {
    /// Builds the snapshot from recent drinks only (performance).
    static func makeSnapshot(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) -> WidgetSnapshot {
        let dayEnd = defaults.object(forKey: SettingsKey.dayEndMinutes) as? Int ?? SettingsDefault.dayEndMinutes
        let boundary = DayBoundary(dayEndMinutes: dayEnd)
        let todayStart = boundary.interval(forLogicalDay: boundary.logicalDay(for: now)).start
        // Earlier drinks can still affect the mood.
        let from = min(todayStart, now.addingTimeInterval(-max(CompanionLogic.drunkWindow, CompanionLogic.caffeineWindow)))
        let descriptor = FetchDescriptor<DrinkEntry>(predicate: #Predicate { $0.timestamp >= from },
                                                     sortBy: [SortDescriptor(\.timestamp)])
        let recent = (try? context.fetch(descriptor)) ?? []
        let presets = (try? context.fetch(FetchDescriptor<DrinkPreset>())) ?? []
        let goalDays = max(defaults.integer(forKey: SettingsKey.dojoBestGoalDays)
                           - defaults.integer(forKey: SettingsKey.prestigeBaseGoalDays), 0)
        return WidgetSnapshot(
            goalML: defaults.object(forKey: SettingsKey.dailyGoalML) as? Double ?? SettingsDefault.dailyGoalML,
            dayEndMinutes: dayEnd,
            beltRaw: Belt.belt(forGoalDays: goalDays).rawValue,
            prestige: defaults.integer(forKey: SettingsKey.prestigeLevel),
            companionEnabled: defaults.object(forKey: SettingsKey.companionEnabled) as? Bool ?? SettingsDefault.companionEnabled,
            recent: recent.map(WidgetDrink.init(entry:)),
            quickDrinks: DrinkStars.widgetDrinks(presets).map { WidgetDrink(preset: $0, now: now) }
        )
    }

    /// Tells the widgets, but only if something changed: `quickDrinks` carry no
    /// meaningful time or id, so those are left out of the comparison.
    static func publish(context: ModelContext, store: UserDefaults = WidgetStore.shared) {
        let snapshot = makeSnapshot(context: context)
        guard !isSame(snapshot, WidgetStore.snapshot(in: store)) else { return }
        WidgetStore.save(snapshot, in: store)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func isSame(_ a: WidgetSnapshot, _ b: WidgetSnapshot?) -> Bool {
        guard let b else { return false }
        func plain(_ s: WidgetSnapshot) -> WidgetSnapshot {
            var s = s
            let fixed = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            s.recent = s.recent.map { var d = $0; d.id = fixed; return d }
            s.quickDrinks = s.quickDrinks.map { var d = $0; d.id = fixed; d.timestamp = .distantPast; return d }
            return s
        }
        return plain(a) == plain(b)
    }

    /// Drinks logged from a widget become real drinks (and go to Health from here).
    static func drainPending(context: ModelContext, store: UserDefaults = WidgetStore.shared) {
        let pending = WidgetStore.pending(in: store)
        guard !pending.isEmpty else { return }
        pending.forEach { context.insert($0.makeEntry()) }
        // Only forgotten once they are safely saved.
        guard (try? context.save()) != nil else { return }
        WidgetStore.removePending(ids: Set(pending.map(\.id)), in: store)
    }
}
