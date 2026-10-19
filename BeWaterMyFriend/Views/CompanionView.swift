import SwiftUI

/// The optional ninja-drop companion. It reacts to today's progress but never
/// dies or loses progress.
struct CompanionView: View {
    var progress: Double

    var body: some View {
        HStack(spacing: 14) {
            NinjaDrop(progress: progress)
                .frame(width: 52, height: 64)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ninja drop: \(message)")
    }

    private var message: String {
        switch progress {
        case ..<0.01: "Your training begins. One sip at a time."
        case ..<0.5: "Flow like water, my friend."
        case ..<1: "More than halfway. Keep flowing."
        default: "Goal reached. A true water master!"
        }
    }
}

/// A water drop wearing a ninja headband.
struct NinjaDrop: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Image(systemName: "drop.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor.gradient)
                // Headband
                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: w * 0.78, height: h * 0.16)
                    .offset(y: h * 0.12)
                // Eyes
                HStack(spacing: w * 0.16) {
                    eye
                    eye
                }
                .frame(width: w * 0.5, height: h * 0.08)
                .offset(y: h * 0.12)
            }
            .frame(width: w, height: h)
            .scaleEffect(progress >= 1 ? 1.08 : 1)
            .animation(.spring(duration: 0.5, bounce: 0.5), value: progress >= 1)
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.white)
            .rotationEffect(.degrees(progress >= 1 ? 0 : -8))
    }
}

#Preview {
    VStack(spacing: 24) {
        CompanionView(progress: 0)
        CompanionView(progress: 0.6)
        CompanionView(progress: 1.1)
    }
    .padding()
}
