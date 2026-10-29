import SwiftUI
import UIKit

/// Dojo look: indigo ink, washi-paper background, a red seal for achievements,
/// and a seigaiha (blue ocean wave) pattern.
enum Dojo {
    /// Indigo, same as the app's accent colour.
    static let ink = Color.accentColor
    /// Lighter water blue for fills.
    static let water = Color(light: .init(red: 0.33, green: 0.62, blue: 0.93, alpha: 1),
                             dark: .init(red: 0.36, green: 0.62, blue: 0.95, alpha: 1))
    /// Warm off-white like washi paper; deep night blue in dark mode.
    static let paper = Color(light: .init(red: 0.97, green: 0.955, blue: 0.925, alpha: 1),
                             dark: .init(red: 0.067, green: 0.086, blue: 0.122, alpha: 1))
    /// Card background on top of `paper`.
    static let card = Color(light: .init(white: 1, alpha: 1),
                            dark: .init(red: 0.11, green: 0.135, blue: 0.18, alpha: 1))
    /// Red of a hanko seal, used for achievements.
    static let seal = Color(red: 0.76, green: 0.2, blue: 0.17)
}

extension Color {
    /// `nonisolated` on purpose: during animations SwiftUI resolves colours on
    /// its own render thread. With the app's default main-actor isolation this
    /// closure counted as main-actor code, and Swift's runtime check stopped the
    /// app whenever it ran off the main thread (crash found 29 Oct, day replay).
    nonisolated init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { @Sendable traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

extension View {
    /// Paper background behind a List or Form.
    func dojoBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Dojo.paper)
    }
}

/// Seigaiha: overlapping rows of concentric half-circles, like stylised waves.
struct SeigaihaPattern: View {
    var color: Color = Dojo.ink
    var radius: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let rings = 4
            let rowHeight = radius * 0.5
            var row = 0
            var y: CGFloat = 0
            while y < size.height + radius {
                let offset = row.isMultiple(of: 2) ? 0 : radius
                var x = -radius + offset
                while x < size.width + radius {
                    for ring in 0..<rings {
                        let r = radius * CGFloat(rings - ring) / CGFloat(rings)
                        var path = Path()
                        path.addArc(center: CGPoint(x: x, y: y), radius: r,
                                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                        context.stroke(path, with: .color(color), lineWidth: 1)
                    }
                    x += radius * 2
                }
                y += rowHeight
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SeigaihaPattern()
        .opacity(0.3)
        .frame(height: 200)
}
