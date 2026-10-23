import SwiftUI

/// The ninja drop on the Today screen: fills up with today's drinks (in their
/// colours), reacts to what was drunk, wears its belt, and opens the dojo when tapped.
struct CompanionView: View {
    var progress: Double
    var layers: [FillLayer]
    var mood: CompanionMood
    var belt: Belt
    var prestige: Int
    var stats: DojoStats
    var goalDaysTowardBelt: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                NinjaDrop(progress: progress, belt: belt, layers: layers, mood: mood, prestige: prestige)
                    .frame(width: 64, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.callout)
                    HStack(spacing: 6) {
                        BeltBadge(belt: belt)
                        Text(belt.name)
                            .font(.caption.weight(.semibold))
                        if prestige > 0 {
                            Text("★\(prestige)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Dojo.seal)
                        }
                        if stats.currentStreak > 1 {
                            Text("· \(stats.currentStreak)-day streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let next = belt.next {
                        let remaining = max(next.requiredGoalDays - goalDaysTowardBelt, 0)
                        Text("\(Format.count(remaining, "goal day", "goal days")) to \(next.isDan ? next.name : next.name.lowercased())")
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
        switch mood {
        case .drunk: return "Whoa… the room is spinning. Water break?"
        case .tipsy: return "Feeling a bit wobbly… hic!"
        case .hyper: return "Caffeine rush! Zoom zoom!"
        case .strong: return "Protein power! Feeling strong."
        case .charged: return "Fully charged with electrolytes!"
        case .calm: break
        }
        switch progress {
        case ..<0.01: return "Your training begins. One sip at a time."
        case ..<0.5: return "Flow like water, my friend."
        case ..<1: return "More than halfway. Keep flowing."
        default: return "Goal reached. Well trained!"
        }
    }
}

/// A water drop in a ninja mask. It fills with today's drinks in their colours,
/// grows as it fills, shows its belt in the headband tails, and reacts to its mood.
struct NinjaDrop: View {
    var progress: Double
    var belt: Belt
    /// Coloured bands; `nil` shows a single water band at `progress`.
    var layers: [FillLayer]? = nil
    var mood: CompanionMood = .calm
    var prestige: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 2
            let jitter = mood == .hyper && !reduceMotion && CompanionLogic.isJitterBurst(at: timeline.date)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    if jitter { speedLines(w: w, h: h, phase: phase) }
                    if mood == .strong { arms(w: w, h: h, phase: phase) }
                    tails(w: w, h: h, phase: phase)

                    DropShape().fill(Dojo.card)
                    fill(phase: phase)
                        .clipShape(DropShape())
                    DropShape().stroke(Dojo.ink, lineWidth: max(w * 0.045, 1.5))

                    if mood == .tipsy || mood == .drunk {
                        // Rosy cheeks under the mask.
                        let blush = Color.pink.opacity(mood == .drunk ? 0.85 : 0.55)
                        HStack(spacing: w * 0.34) {
                            Ellipse().fill(blush)
                            Ellipse().fill(blush)
                        }
                        .frame(width: w * 0.7, height: h * 0.06)
                        .offset(y: h * 0.27)
                    }

                    // Mask band with eyes.
                    Capsule()
                        .fill(Color(white: 0.12))
                        .frame(width: w * 0.92, height: h * 0.17)
                        .offset(y: h * 0.12)
                    HStack(spacing: w * 0.16) {
                        Eye(style: eyeStyle)
                        Eye(style: eyeStyle, mirrored: true)
                    }
                    .frame(width: w * 0.52, height: h * 0.075)
                    .offset(y: h * 0.12)

                    if mood == .charged { sparks(w: w, h: h, phase: phase) }
                    if prestige > 0 { prestigeSeal(w: w, h: h) }
                }
                .frame(width: w, height: h)
                .rotationEffect(.degrees(sway(phase: phase)), anchor: .bottom)
                .offset(x: jitter ? sin(phase * 22) * w * 0.025 : (mood == .drunk ? sin(phase * 0.8) * w * 0.05 : 0))
            }
        }
        .scaleEffect(DojoProgress.companionScale(progress: progress), anchor: .bottom)
        .animation(.spring(duration: 0.6, bounce: 0.4), value: progress)
        .accessibilityHidden(true)
    }

    private func sway(phase: Double) -> Double {
        switch mood {
        case .tipsy: sin(phase * 0.6) * 9
        case .drunk: sin(phase * 1.1) * 16
        default: 0
        }
    }

    private var eyeStyle: Eye.Style {
        switch mood {
        case .hyper: .wide
        case .tipsy: .sleepy
        case .drunk: .dizzy
        default: progress >= 1 ? .happy : .focused
        }
    }

    /// Stacked coloured bands, the top one with a gentle wave.
    @ViewBuilder
    private func fill(phase: Double) -> some View {
        let bands = layers ?? (progress > 0 ? [FillLayer(tint: .water, fraction: min(progress, 1))] : [])
        ZStack {
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                let bottom = bands.prefix(index).reduce(0) { $0 + $1.fraction }
                FillBand(from: bottom, to: bottom + band.fraction, phase: phase, wavy: index == bands.count - 1)
                    .fill(band.tint.color.gradient)
            }
        }
    }

    private func tails(w: Double, h: Double, phase: Double) -> some View {
        ForEach(0..<2) { i in
            Capsule()
                .fill(i == 0 ? belt.color : belt.secondaryColor)
                .overlay(alignment: .trailing) {
                    if let metal = belt.metalColor {
                        Capsule().fill(metal).frame(width: w * 0.1)
                    }
                }
                .overlay(Capsule().stroke(Color.black.opacity(belt == .white ? 0.35 : 0), lineWidth: 1))
                .frame(width: w * 0.36, height: h * 0.075)
                .rotationEffect(.degrees(Double(i == 0 ? 18 : 40) + sin(phase * 1.5 + Double(i)) * 6), anchor: .leading)
                .offset(x: w * 0.62, y: h * 0.12)
        }
    }

    /// Little flexing arms for protein.
    private func arms(w: Double, h: Double, phase: Double) -> some View {
        ForEach([-1.0, 1.0], id: \.self) { side in
            ZStack(alignment: .top) {
                Capsule().fill(Dojo.water).frame(width: w * 0.14, height: h * 0.26)
                Circle().fill(Dojo.water).frame(width: w * 0.2, height: w * 0.2).offset(y: -h * 0.03)
            }
            .overlay(Capsule().stroke(Dojo.ink, lineWidth: 1.2).frame(width: w * 0.14, height: h * 0.26))
            .rotationEffect(.degrees(side * (35 + sin(phase * 3) * 12)), anchor: .bottom)
            .offset(x: side * w * 0.5, y: h * 0.18)
        }
    }

    private func speedLines(w: Double, h: Double, phase: Double) -> some View {
        ForEach(0..<3) { i in
            Capsule()
                .fill(Dojo.ink.opacity(0.35))
                .frame(width: w * (0.18 + 0.06 * Double(i % 2)), height: 2)
                .offset(x: -w * 0.62 + sin(phase * 8 + Double(i)) * 3, y: h * (0.0 + 0.12 * Double(i)))
        }
    }

    private func sparks(w: Double, h: Double, phase: Double) -> some View {
        ForEach(0..<3) { i in
            let angle = Double(i) * 2.1 + 0.6
            Image(systemName: "bolt.fill")
                .font(.system(size: w * 0.18))
                .foregroundStyle(.yellow)
                .opacity(0.5 + 0.5 * sin(phase * 3 + Double(i) * 2))
                .offset(x: cos(angle) * w * 0.62, y: sin(angle) * h * 0.42 - h * 0.05)
        }
    }

    private func prestigeSeal(w: Double, h: Double) -> some View {
        Text("\(prestige)")
            .font(.system(size: w * 0.17, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .frame(width: w * 0.3, height: w * 0.3)
            .background(Dojo.seal, in: .rect(cornerRadius: w * 0.06))
            .offset(x: w * 0.38, y: -h * 0.36)
    }
}

private struct Eye: View {
    enum Style { case focused, happy, wide, sleepy, dizzy }
    var style: Style
    var mirrored = false

    var body: some View {
        switch style {
        case .happy:
            HappyEyeShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .wide:
            Circle().fill(Color.white).scaleEffect(1.5)
        case .sleepy:
            Capsule().fill(Color.white).scaleEffect(x: 1, y: 0.35).offset(y: 2)
        case .dizzy:
            // × eyes
            ZStack {
                Capsule().fill(Color.white).frame(height: 2.5).rotationEffect(.degrees(40))
                Capsule().fill(Color.white).frame(height: 2.5).rotationEffect(.degrees(-40))
            }
            .scaleEffect(0.8)
        case .focused:
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

/// A horizontal band of liquid from `from` to `to` (0 = bottom, 1 = top),
/// optionally with a wave on top.
nonisolated struct FillBand: Shape {
    var from: Double
    var to: Double
    var phase: Double
    var wavy: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(from, to) }
        set { from = newValue.first; to = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        guard to > from else { return Path() }
        let bottom = rect.maxY - rect.height * from
        let surface = rect.maxY - rect.height * to
        let amplitude = wavy && to < 1 ? rect.height * 0.025 : 0
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX, y: surface))
        let steps = 24
        for step in 0...steps {
            let x = rect.minX + rect.width * Double(step) / Double(steps)
            let y = surface + sin(phase + Double(step) / Double(steps) * .pi * 2) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        p.closeSubpath()
        return p
    }
}

extension DrinkTint {
    var color: Color {
        switch self {
        case .water: Dojo.water
        case .coffee: Color(red: 0.6, green: 0.4, blue: 0.24)
        case .tea: Color(red: 0.8, green: 0.58, blue: 0.2)
        case .juice: Color(red: 0.96, green: 0.62, blue: 0.2)
        case .soda: Color(red: 0.75, green: 0.33, blue: 0.2)
        case .energy: Color(red: 0.7, green: 0.82, blue: 0.22)
        case .milk: Color(red: 0.94, green: 0.9, blue: 0.82)
        case .electrolytes: Color(red: 0.36, green: 0.82, blue: 0.7)
        case .beer: Color(red: 0.96, green: 0.78, blue: 0.2)
        case .wine: Color(red: 0.56, green: 0.17, blue: 0.28)
        case .spirits: Color(red: 0.82, green: 0.54, blue: 0.18)
        }
    }
}

/// A small belt: plain colour, black with gold stripes for 1st–5th Dan,
/// red-and-white for 6th–8th Dan, red for 9th–10th Dan. Ranks that share a
/// belt colour get a bronze, silver or gold edge so they look different.
struct BeltBadge: View {
    var belt: Belt

    var body: some View {
        ZStack {
            if belt == .dan6 || belt == .dan7 || belt == .dan8 {
                HStack(spacing: 0) {
                    ForEach(0..<6) { i in
                        Rectangle().fill(i.isMultiple(of: 2) ? belt.color : belt.secondaryColor)
                    }
                }
            } else {
                Rectangle().fill(belt.color)
            }
            if let level = belt.danLevel, level <= 5 {
                HStack(spacing: 1.5) {
                    ForEach(0..<level, id: \.self) { _ in
                        Rectangle().fill(belt.secondaryColor).frame(width: 1.5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 2)
            }
        }
        .clipShape(.rect(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(belt == .white ? 0.35 : 0), lineWidth: 1))
        .overlay {
            if let metal = belt.metalColor {
                RoundedRectangle(cornerRadius: 2.5).stroke(metal, lineWidth: 1.6).padding(-1.2)
            }
        }
        .frame(width: 22, height: 6)
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
        case .black, .dan1, .dan2, .dan3, .dan4, .dan5: Color(white: 0.11)
        case .dan6, .dan7, .dan8, .dan9, .dan10: Color(red: 0.8, green: 0.15, blue: 0.14)
        }
    }

    /// Edge for ranks that share a belt colour: 6th/7th/8th Dan bronze/silver/gold,
    /// 9th/10th Dan silver/gold.
    var metalColor: Color? {
        switch self {
        case .dan6: Color(red: 0.72, green: 0.45, blue: 0.2)
        case .dan7, .dan9: Color(red: 0.78, green: 0.8, blue: 0.84)
        case .dan8, .dan10: Color(red: 0.95, green: 0.78, blue: 0.25)
        default: nil
        }
    }

    /// Second colour: gold stripes, white blocks, or the same red.
    var secondaryColor: Color {
        switch self {
        case .dan1, .dan2, .dan3, .dan4, .dan5: Color(red: 0.88, green: 0.72, blue: 0.3)
        case .dan6, .dan7, .dan8: .white
        default: color
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

#Preview("Moods") {
    let layers = [FillLayer(tint: .water, fraction: 0.3), FillLayer(tint: .coffee, fraction: 0.15),
                  FillLayer(tint: .beer, fraction: 0.2)]
    VStack(spacing: 30) {
        HStack(spacing: 34) {
            NinjaDrop(progress: 0.65, belt: .white, layers: layers, mood: .calm).frame(width: 64, height: 84)
            NinjaDrop(progress: 0.65, belt: .green, layers: layers, mood: .hyper).frame(width: 64, height: 84)
            NinjaDrop(progress: 0.65, belt: .black, layers: layers, mood: .tipsy).frame(width: 64, height: 84)
            NinjaDrop(progress: 0.65, belt: .dan8, layers: layers, mood: .drunk).frame(width: 64, height: 84)
        }
        HStack(spacing: 34) {
            NinjaDrop(progress: 1, belt: .dan3, mood: .strong).frame(width: 64, height: 84)
            NinjaDrop(progress: 1, belt: .dan7, mood: .charged).frame(width: 64, height: 84)
            NinjaDrop(progress: 1, belt: .dan10, prestige: 2).frame(width: 64, height: 84)
        }
    }
    .padding(40)
}
