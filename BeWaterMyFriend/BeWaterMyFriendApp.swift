import SwiftData
import SwiftUI
import UserNotifications

@main
struct BeWaterMyFriendApp: App {
    let container: ModelContainer
    /// Kept alive here: the notification center only holds a weak reference.
    private let notificationHandler: NotificationHandler

    init() {
        if AppEnvironment.isUITest {
            // Sample drinks in memory: the real database is never opened.
            container = PreviewData.container
        } else {
            do {
                container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                               configurations: Self.storeConfiguration)
            } catch {
                fatalError("Could not open the drink database: \(error)")
            }
            DefaultPresets.seedIfNeeded(in: container.mainContext)
            if let presets = try? container.mainContext.fetch(FetchDescriptor<DrinkPreset>()),
               DrinkStars.migrateOldFavourites(presets) {
                try? container.mainContext.save()
            }
        }
        notificationHandler = NotificationHandler(container: container)
        UNUserNotificationCenter.current().delegate = notificationHandler
    }

    /// `groupContainer: .none` is essential: with an App Group in the entitlements,
    /// SwiftData would otherwise silently open a new, empty database in the shared
    /// folder, and the user's drinks would look gone (found 31 Oct, before release).
    static let storeConfiguration = ModelConfiguration(groupContainer: .none)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .defaultAppStorage(AppEnvironment.isUITest ? AppEnvironment.testDefaults : .standard)
        }
        .modelContainer(container)
    }
}

/// Automated UI tests (BeWaterMyFriendUITests) launch the app with `-UITestMode`.
/// The app then uses sample drinks in memory and separate, empty settings, and
/// skips Health, weather and reminders, so a test run on the real iPhone never
/// touches the user's drinks, settings, ranks or Health data. Debug builds only.
enum AppEnvironment {
    static let uiTestFlag = "-UITestMode"

    static var isUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(uiTestFlag)
        #else
        false
        #endif
    }

    /// UI test for the black belt moment, which normally takes months to reach.
    static var showsBlackBeltForTest: Bool {
        isUITest && ProcessInfo.processInfo.arguments.contains("-UITestBlackBelt")
    }

    /// Wiped at every launch, so each test run starts from the defaults.
    static let testDefaults: UserDefaults = {
        let name = "BeWaterMyFriend-UITests"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }()
}
