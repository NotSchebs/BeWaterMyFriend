import SwiftData
import SwiftUI

/// In-memory sample data for SwiftUI previews.
enum PreviewData {
    @MainActor static let container: ModelContainer = {
        let container = try! ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        DefaultPresets.make().forEach { context.insert($0) }
        let presets = DefaultPresets.make()
        for daysAgo in 0..<10 {
            let base = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            for (index, preset) in presets.prefix(4 + daysAgo % 3).enumerated() {
                let time = Calendar.current.date(bySettingHour: 8 + index * 2, minute: 0, second: 0, of: base)!
                if time <= .now { context.insert(preset.makeEntry(at: time)) }
            }
        }
        return container
    }()
}
