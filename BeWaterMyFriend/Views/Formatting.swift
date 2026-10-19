import Foundation
import SwiftData

enum Format {
    static func ml(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) ml"
    }

    static func mg(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) mg"
    }

    static func amount(_ value: Double, unit: String) -> String {
        let digits = value < 10 ? 2 : (value < 100 ? 1 : 0)
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(unit)"
    }

    static func standardDrinks(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// "1 day", "3 days".
    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    static func percent(_ progress: Double) -> String {
        progress.formatted(.percent.precision(.fractionLength(0)))
    }
}

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
