import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.healthSyncEnabled) private var healthEnabled = false
    @AppStorage(SettingsKey.healthWriteDelay) private var delayRaw = HealthWriteDelay.oneHour.rawValue
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue
    @State private var selectedTab = AppTab.today
    @State private var saveWork: Task<Void, Never>?
    private var router = AppRouter.shared

    enum AppTab: Hashable { case today, history, stats, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "drop.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Stats", systemImage: "chart.bar.fill", value: AppTab.stats) {
                StatsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // Links: bewatermyfriend://new and bewatermyfriend://scan (same path as the reminder buttons).
        .onOpenURL { url in
            switch url.host() {
            case "new": router.pendingAction = .newDrink
            case "scan": router.pendingAction = .scan
            default: break
            }
        }
        // A reminder's "New drink" or "Scan" opens the Today tab, which shows the screen.
        .onChange(of: router.pendingAction, initial: true) { _, action in
            if action != nil { selectedTab = .today }
        }
        // "Logged … · Undo" pinned to the bottom of the screen, whatever is scrolled
        // where. It sits above the whole TabView, so no list can catch its taps.
        .overlay(alignment: .bottom) {
            if let entry = router.lastLogged {
                LoggedToast(entry: entry) {
                    EntryActions.delete([entry], in: context)
                    withAnimation { router.lastLogged = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 74)  // just above the tab bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: router.lastLogged?.persistentModelID)
        .fontDesign(.rounded)
        .preferredColorScheme(colorScheme)
        // While the app is open, check every minute for drinks whose Health delay has passed.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Spread the startup work out instead of doing everything at once
            // (performance): the screen comes first, background jobs follow.
            try? await Task.sleep(for: .seconds(1))
            await syncHealth()
            try? await Task.sleep(for: .seconds(2))
            await GoalService.shared.refresh()
            try? await Task.sleep(for: .seconds(2))
            await ReminderScheduler.shared.reschedule(context: context)
            try? await Task.sleep(for: .seconds(55))
            while !Task.isCancelled {
                await syncHealth()
                await GoalService.shared.refresh()  // new workouts, a new day (weather is cached)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        // And right after any change, so "Immediately" really is immediate.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            // Several saves in a row (e.g. a sync writing many drinks) trigger one run.
            saveWork?.cancel()
            saveWork = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await syncHealth()
                // Progress and the "last drink" button changed: re-plan reminders.
                await ReminderScheduler.shared.reschedule(context: context)
            }
        }
    }

    /// `nil` follows the system setting.
    private var colorScheme: ColorScheme? {
        switch Appearance(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func syncHealth() async {
        guard healthEnabled else { return }
        await HealthSync.shared.sync(context: context,
                                     delay: HealthWriteDelay(rawValue: delayRaw) ?? .oneHour,
                                     boundary: DayBoundary(dayEndMinutes: dayEndMinutes))
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
