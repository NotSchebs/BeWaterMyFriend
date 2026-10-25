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
    private var router = AppRouter.shared

    enum AppTab: Hashable { case today, history, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "drop.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // A reminder's "New drink" or "Scan" opens the Today tab, which shows the screen.
        .onChange(of: router.pendingAction, initial: true) { _, action in
            if action != nil { selectedTab = .today }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(colorScheme)
        // While the app is open, check every minute for drinks whose Health delay has passed.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await ReminderScheduler.shared.reschedule(context: context)
            while !Task.isCancelled {
                await syncHealth()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        // And right after any change, so "Immediately" really is immediate.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task {
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
