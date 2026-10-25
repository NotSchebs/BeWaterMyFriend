import Foundation
import Observation
import SwiftData
import UserNotifications

/// Where the app should go after a reminder action that opens it.
enum QuickAction: Equatable {
    case newDrink
    case scan
}

/// Tells the UI to open a screen (e.g. after tapping "Scan" on a reminder).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var pendingAction: QuickAction?
}

/// Schedules drink reminders as local notifications. iOS can't run our code at
/// reminder time, so reminders are planned ahead (today and the next days) and
/// re-planned whenever the app opens or a drink changes.
///
/// Apple documentation:
/// - https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
/// - https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    static let categoryID = "drinkReminder"
    enum ActionID {
        static let logLast = "logLast"
        static let newDrink = "newDrink"
        static let scan = "scan"
    }

    /// iOS keeps at most 64 pending local notifications per app.
    private let maxPending = 60
    private let daysAhead = 6
    private let center = UNUserNotificationCenter.current()

    private let messages = [
        "Flow like water, my friend. Time for a sip.",
        "Your ninja drop is getting thirsty.",
        "A quick drink keeps the training going.",
        "Water break! One glass, then back to it.",
        "Stay sharp: have something to drink.",
    ]

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func settings(from defaults: UserDefaults = .standard) -> ReminderSettings {
        var s = ReminderSettings()
        if defaults.object(forKey: SettingsKey.reminderStartMinutes) != nil {
            s.startMinutes = defaults.integer(forKey: SettingsKey.reminderStartMinutes)
        }
        if defaults.object(forKey: SettingsKey.reminderEndMinutes) != nil {
            s.endMinutes = defaults.integer(forKey: SettingsKey.reminderEndMinutes)
        }
        if defaults.object(forKey: SettingsKey.reminderIntervalMinutes) != nil {
            s.intervalMinutes = defaults.integer(forKey: SettingsKey.reminderIntervalMinutes)
        }
        if defaults.object(forKey: SettingsKey.reminderSmart) != nil {
            s.smart = defaults.bool(forKey: SettingsKey.reminderSmart)
        }
        if defaults.object(forKey: SettingsKey.reminderSkipOnTrack) != nil {
            s.skipWhenOnTrack = defaults.bool(forKey: SettingsKey.reminderSkipOnTrack)
        }
        return s
    }

    /// Replaces all pending reminders with a fresh plan.
    func reschedule(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) async {
        center.removeAllPendingNotificationRequests()
        guard defaults.bool(forKey: SettingsKey.remindersEnabled) else { return }

        let settings = Self.settings(from: defaults)
        let calendar = Calendar.current
        let entries = (try? context.fetch(FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? []
        registerCategory(lastDrink: entries.first)

        // Today's progress, for "skip when on track".
        let goal = defaults.object(forKey: SettingsKey.dailyGoalML) as? Double ?? SettingsDefault.dailyGoalML
        let boundary = DayBoundary(dayEndMinutes: defaults.integer(forKey: SettingsKey.dayEndMinutes))
        let today = boundary.logicalDay(for: now)
        let progress = Summaries.summary(forLogicalDay: today, entries: entries, boundary: boundary).progress(goalML: goal)

        var generator = SystemRandomNumberGenerator()
        var times: [Date] = []
        for offset in 0...daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let planned = ReminderPlanner.times(on: day, settings: settings, calendar: calendar, using: &generator)
            times += offset == 0
                ? ReminderPlanner.todaysTimes(planned, now: now, progress: progress, settings: settings, calendar: calendar)
                : planned
        }

        for (index, time) in times.prefix(maxPending).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "BeWaterMyFriend"
            content.body = messages[index % messages.count]
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
            let request = UNNotificationRequest(identifier: "reminder-\(index)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }

    /// The buttons shown when long-pressing a reminder. "Log again" names the
    /// last drink and works without opening the app.
    private func registerCategory(lastDrink: DrinkEntry?) {
        var actions: [UNNotificationAction] = []
        if let last = lastDrink {
            actions.append(UNNotificationAction(identifier: ActionID.logLast,
                                                title: "Log \(last.name) (\(Format.ml(last.volumeML))) again",
                                                options: []))
        }
        actions.append(UNNotificationAction(identifier: ActionID.newDrink, title: "New drink", options: [.foreground]))
        actions.append(UNNotificationAction(identifier: ActionID.scan, title: "Scan", options: [.foreground]))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: [])
        ])
    }
}

/// Handles taps on reminders and their buttons.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case ReminderScheduler.ActionID.logLast: logLastDrinkAgain()
            case ReminderScheduler.ActionID.newDrink: AppRouter.shared.pendingAction = .newDrink
            case ReminderScheduler.ActionID.scan: AppRouter.shared.pendingAction = .scan
            default: break  // plain tap just opens the app
            }
        }
    }

    /// Show reminders even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Copies the most recent drink with the current time.
    @MainActor
    private func logLastDrinkAgain() {
        let context = container.mainContext
        var newest = FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = 1
        guard let last = try? context.fetch(newest).first else { return }
        var draft = DrinkDraft(entry: last)
        draft.timestamp = .now
        draft.source = last.source == .scan ? .scan : .manual
        draft.barcode = last.barcode
        context.insert(draft.makeEntry())
        try? context.save()
    }
}
