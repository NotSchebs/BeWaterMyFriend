import Foundation

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
