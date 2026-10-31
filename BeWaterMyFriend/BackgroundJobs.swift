import SwiftData
import SwiftUI

/// What the app does in the background while it's open: write drinks to Health,
/// refresh the suggested goal, re-plan reminders. ContentView only says when.
///
/// Startup is spread out (performance: the screen comes first), then Health and
/// the goal are checked every minute. After a save, Health and reminders run once.
enum BackgroundJobs {
    /// Runs until the task is cancelled (the app leaves the foreground).
    static func whileActive(context: ModelContext) async {
        try? await Task.sleep(for: .seconds(1))
        await syncHealth(context: context)
        try? await Task.sleep(for: .seconds(2))
        await GoalService.shared.refresh()
        try? await Task.sleep(for: .seconds(2))
        await ReminderScheduler.shared.reschedule(context: context)
        WidgetBridge.publish(context: context)
        try? await Task.sleep(for: .seconds(55))
        while !Task.isCancelled {
            await syncHealth(context: context)
            await GoalService.shared.refresh()  // new workouts, a new day (weather is cached)
            WidgetBridge.publish(context: context)  // does nothing if nothing changed
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// After a change, so "Immediately" really is immediate, and reminders know
    /// the new progress and "last drink".
    static func afterSave(context: ModelContext) async {
        WidgetBridge.publish(context: context)
        await syncHealth(context: context)
        await ReminderScheduler.shared.reschedule(context: context)
    }

    /// Writes due drinks to Health, if the user turned Health on.
    static func syncHealth(context: ModelContext, defaults: UserDefaults = .standard) async {
        guard defaults.bool(forKey: SettingsKey.healthSyncEnabled) else { return }
        let delay = defaults.string(forKey: SettingsKey.healthWriteDelay).flatMap(HealthWriteDelay.init) ?? .oneHour
        let dayEnd = defaults.object(forKey: SettingsKey.dayEndMinutes) as? Int ?? SettingsDefault.dayEndMinutes
        await HealthSync.shared.sync(context: context, delay: delay, boundary: DayBoundary(dayEndMinutes: dayEnd))
    }
}
