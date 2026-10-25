import SwiftData
import SwiftUI
import UserNotifications

@main
struct BeWaterMyFriendApp: App {
    let container: ModelContainer
    /// Kept alive here: the notification center only holds a weak reference.
    private let notificationHandler: NotificationHandler

    init() {
        do {
            container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self)
        } catch {
            fatalError("Could not open the drink database: \(error)")
        }
        DefaultPresets.seedIfNeeded(in: container.mainContext)
        notificationHandler = NotificationHandler(container: container)
        UNUserNotificationCenter.current().delegate = notificationHandler
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
