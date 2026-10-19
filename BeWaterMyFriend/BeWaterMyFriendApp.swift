import SwiftData
import SwiftUI

@main
struct BeWaterMyFriendApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self)
        } catch {
            fatalError("Could not open the drink database: \(error)")
        }
        DefaultPresets.seedIfNeeded(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
