import SwiftUI

/// The ninja drop on the Today screen: fills up and grows with today's water,
/// wears its belt colour, and opens the dojo when tapped.
struct CompanionView: View {
    var progress: Double
    var belt: Belt
    var stats: DojoStats
    var goalDaysTowardBelt: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                NinjaDrop(progress: progress, belt: belt)
                    .frame(width: 64, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.callout)
                    HStack(spacing: 6) {
                        BeltBadge(belt: belt)
                        Text(belt.name)
                            .font(.caption.weight(.semibold))
                        if stats.currentStreak > 1 {
                            Text("· \(stats.currentStreak)-day streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let next = belt.next {
                        let remaining = max(next.requiredGoalDays - goalDaysTowardBelt, 0)
                        Text("\(Format.count(remaining, "goal day", "goal days")) to \(next.name.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ninja drop, \(belt.name). \(message)")
        .accessibilityHint("Opens the dojo")
    }

    private var message: String {
        switch progress {
        case ..<0.01: "Your training begins. One sip at a time."
        case ..<0.5: "Flow like water, my friend."
        case ..<1: "More than halfway. Keep flowing."
        default: "Goal reached. Well trained!"
        }
    }
}

/// A water drop in a ninja mask. The water level shows today's progress, the
/// drop grows a little as it fills, and the headband tails show the belt.
struct NinjaDrop: View {
    var progress: Double
    var belt: Belt

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 2
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    DropShape().fill(Dojo.card)
                    WaterFill(level: min(max(progress, 0), 1), phase: phase)
                        .fill(Dojo.water.gradient)
                        .clipShape(DropShape())
                    DropShape().stroke(Dojo.ink, lineWidth: max(w * 0.045, 1.5))

                    // Headband tails in the belt colour, fluttering at the back.
                    ForEach(0..<2) { i in
                        Capsule()
                            .fill(belt.color)
                            .overlay(Capsule().stroke(Color.black.opacity(belt == .white ? 0.35 : 0), lineWidth: 1))
                            .frame(width: w * 0.36, height: h * 0.075)
                            .rotationEffect(.degrees(Double(i == 0 ? 18 : 40) + sin(phase * 1.5 + Double(i)) * 6),
                                            anchor: .leading)
                            .offset(x: w * 0.62, y: h * 0.12)
                    }

                    // Mask band with eyes.
                    Capsule()
                        .fill(Color(white: 0.12))
                        .frame(width: w * 0.92, height: h * 0.17)
                        .offset(y: h * 0.12)
                    HStack(spacing: w * 0.16) {
                        Eye(happy: progress >= 1)
                        Eye(happy: progress >= 1, mirrored: true)
                    }
                    .frame(width: w * 0.52, height: h * 0.075)
                    .offset(y: h * 0.12)
                }
                .frame(width: w, height: h)
            }
        }
        .scaleEffect(DojoProgress.companionScale(progress: progress), anchor: .bottom)
        .animation(.spring(duration: 0.6, bounce: 0.4), value: progress)
        .accessibilityHidden(true)
    }
}

private struct Eye: View {
    var happy: Bool
    var mirrored = false

    var body: some View {
        if happy {
            // ^ ^ happy eyes
            HappyEyeShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        } else {
            Capsule()
                .fill(Color.white)
                .rotationEffect(.degrees(mirrored ? -10 : 10))
        }
    }
}

private nonisolated struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return p
    }
}

/// Teardrop: a point at the top and a round bottom.
nonisolated struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = w / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY - r)
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: center.y),
                   control1: CGPoint(x: rect.midX + w * 0.08, y: rect.minY + h * 0.2),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.4))
        p.addArc(center: center, radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.4),
                   control2: CGPoint(x: rect.midX - w * 0.08, y: rect.minY + h * 0.2))
        p.closeSubpath()
        return p
    }
}

/// Water from the bottom up to `level` (0…1), with a gentle wave on top.
nonisolated struct WaterFill: Shape {
    var level: Double
    var phase: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard level > 0 else { return Path() }
        let surface = rect.maxY - rect.height * level
        let amplitude = level < 1 ? rect.height * 0.025 : 0
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: surface))
        let steps = 24
        for step in 0...steps {
            let x = rect.minX + rect.width * Double(step) / Double(steps)
            let y = surface + sin(phase + Double(step) / Double(steps) * .pi * 2) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct BeltBadge: View {
    var belt: Belt

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(belt.color)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(belt == .white ? 0.35 : 0), lineWidth: 1))
            .frame(width: 18, height: 6)
            .accessibilityHidden(true)
    }
}

extension Belt {
    var color: Color {
        switch self {
        case .white: Color(white: 0.97)
        case .yellow: Color(red: 0.96, green: 0.77, blue: 0.19)
        case .orange: Color(red: 0.95, green: 0.55, blue: 0.16)
        case .green: Color(red: 0.23, green: 0.65, blue: 0.36)
        case .blue: Color(red: 0.18, green: 0.44, blue: 0.87)
        case .purple: Color(red: 0.56, green: 0.27, blue: 0.68)
        case .brown: Color(red: 0.55, green: 0.35, blue: 0.17)
        case .black: Color(white: 0.11)
        }
    }
}

/// Droplets bursting outward once, used when the goal is reached.
struct SplashBurst: View {
    var trigger: Int
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<10) { i in
                let angle = Double(i) / 10 * 2 * .pi
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(Dojo.water)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: animate ? cos(angle) * 70 : 0, y: animate ? sin(angle) * 70 : 0)
                    .opacity(animate ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            animate = false
            withAnimation(.easeOut(duration: 0.9)) { animate = true }
        }
        .opacity(trigger == 0 ? 0 : 1)
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            NinjaDrop(progress: 0, belt: .white).frame(width: 64, height: 84)
            NinjaDrop(progress: 0.5, belt: .green).frame(width: 64, height: 84)
            NinjaDrop(progress: 1.2, belt: .black).frame(width: 64, height: 84)
        }
        CompanionView(progress: 0.6, belt: .yellow, stats: DojoStats(goalDays: 5, currentStreak: 3, bestStreak: 4),
                      goalDaysTowardBelt: 5, onTap: {})
    }
    .padding()
}
