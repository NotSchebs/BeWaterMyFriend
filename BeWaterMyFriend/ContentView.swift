import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.healthSyncEnabled) private var healthEnabled = false
    @AppStorage(SettingsKey.healthWriteDelay) private var delayRaw = HealthWriteDelay.oneHour.rawValue
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes

    var body: some View {
        TabView {
            Tab("Today", systemImage: "drop.fill") {
                TodayView()
            }
            Tab("History", systemImage: "calendar") {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .fontDesign(.rounded)
        // While the app is open, check every minute for drinks whose Health delay has passed.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await syncHealth()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        // And right after any change, so "Immediately" really is immediate.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await syncHealth() }
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
