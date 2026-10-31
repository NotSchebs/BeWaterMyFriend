import AppIntents
import WidgetKit

// What the widget buttons do. Apple documentation:
// https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities

// Why "+" isn't here: iOS doesn't let a widget's intent open the app
// ("openAppWhenRun is not supported in extensions"), so it's a link. See PlusButton.

/// A starred drink's button: leaves a note for the app, and the widget updates.
struct LogQuickDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a starred drink"
    static let isDiscoverable = false

    @Parameter(title: "Position")
    var position: Int

    init() {}

    init(position: Int) {
        self.position = position
    }

    func perform() async throws -> some IntentResult {
        let drinks = WidgetStore.snapshot()?.quickDrinks ?? []
        if drinks.indices.contains(position) {
            var drink = drinks[position]
            drink.id = UUID()
            drink.timestamp = .now
            WidgetStore.addPending(drink)
        }
        return .result()
    }
}
