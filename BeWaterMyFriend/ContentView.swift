import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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
            case "add": router.pendingAction = .addDrink
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
        // Widgets: on opening, turn drinks logged from a widget into real ones and
        // follow its "+"; on leaving, leave them today's numbers.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard !AppEnvironment.isUITest else { return }
            if phase == .active {
                WidgetBridge.drainPending(context: context)
                WidgetBridge.publish(context: context)
            } else if phase == .background {
                WidgetBridge.publish(context: context)
            }
        }
        // Background work (Health, goal, reminders): see BackgroundJobs. Skipped in UI tests.
        .task(id: scenePhase) {
            guard scenePhase == .active, !AppEnvironment.isUITest else { return }
            await BackgroundJobs.whileActive(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            guard !AppEnvironment.isUITest else { return }
            // Several saves in a row (e.g. a sync writing many drinks) trigger one run.
            saveWork?.cancel()
            saveWork = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await BackgroundJobs.afterSave(context: context)
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
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
