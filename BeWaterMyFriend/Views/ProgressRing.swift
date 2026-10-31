import SwiftUI

/// Goal progress ring. With `layers`, the ring is split into the colours of
/// the drinks (same as the ninja drop's fill), in the order they were had.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var layers: [FillLayer]? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(Dojo.ink.opacity(0.15), lineWidth: lineWidth)
            if let layers, !layers.isEmpty {
                ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                    let start = layers.prefix(index).reduce(0) { $0 + $1.fraction }
                    Circle()
                        .trim(from: start, to: min(start + layer.fraction, 1))
                        .stroke(layer.tint.ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(Dojo.ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(duration: 0.6), value: progress)
    }
}

extension DrinkTint {
    /// Water uses the app's indigo on the ring so it stands out from the light track.
    var ringColor: Color {
        self == .water ? Dojo.ink : color
    }
}

#Preview {
    VStack(spacing: 30) {
        ProgressRing(progress: 0.65)
            .frame(width: 160, height: 160)
        ProgressRing(progress: 0.8, layers: [FillLayer(tint: .water, fraction: 0.4), FillLayer(tint: .coffee, fraction: 0.15),
                                             FillLayer(tint: .juice, fraction: 0.1), FillLayer(tint: .beer, fraction: 0.15)])
            .frame(width: 160, height: 160)
    }
    .padding()
}
