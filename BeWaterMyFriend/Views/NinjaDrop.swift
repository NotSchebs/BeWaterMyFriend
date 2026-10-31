import SwiftUI

/// A water drop in a ninja mask. It fills with today's drinks in their colours,
/// grows as it fills, shows its belt in the headband tails, and reacts to its mood.
///
/// All motion uses repeating SwiftUI animations, which Core Animation runs
/// without re-drawing the view. (An earlier version redrew everything 30 times
/// a second and used a full CPU core.)
struct NinjaDrop: View {
    var progress: Double
    var belt: Belt
    /// Coloured bands; `nil` shows a single water band at `progress`.
    var layers: [FillLayer]? = nil
    var mood: CompanionMood = .calm
    var prestige: Int = 0
    /// Increases with every logged drink: a short squash-and-stretch "gulp".
    var reaction: Int = 0
    /// Off for small static drops (History, Stats): no repeating motion, no CPU.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips once when the view appears; every repeating animation runs off it.
    @State private var moving = false
    /// Caffeine jitter: 5 seconds, twice a minute.
    @State private var jittering = false

    private var animate: Bool { animated && moving && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if jittering { speedLines(w: w, h: h) }
                if mood == .strong { arms(w: w, h: h) }
                tails(w: w, h: h)

                DropShape().fill(Dojo.card)
                fill(w: w, h: h)
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

                // Mask band in the belt's colour, with eyes.
                BeltPattern(belt: belt)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(belt.metalColor ?? Color.black.opacity(belt.isLight ? 0.35 : 0),
                                              lineWidth: belt.metalColor == nil ? 1 : 2))
                    .frame(width: w * 0.92, height: h * 0.17)
                    .offset(y: h * 0.12)
                HStack(spacing: w * 0.16) {
                    Eye(style: eyeStyle, color: belt.eyeColor)
                    Eye(style: eyeStyle, mirrored: true, color: belt.eyeColor)
                }
                .frame(width: w * 0.52, height: h * 0.075)
                .offset(y: h * 0.12)

                if mood == .charged { sparks(w: w, h: h) }
                if prestige > 0 { PrestigeStamp(level: prestige).frame(width: w * 0.28, height: w * 0.28).offset(x: w * 0.2, y: -h * 0.4) }
            }
            .frame(width: w, height: h)
            // Sway when tipsy or drunk.
            .rotationEffect(.degrees(animate ? swayAngle : -swayAngle), anchor: .bottom)
            .animation(swayAngle == 0 ? .default : .easeInOut(duration: mood == .drunk ? 1.1 : 1.8).repeatForever(),
                       value: animate)
            // Drunk wobble sideways; caffeine jitter during bursts.
            .offset(x: wobble(w: w))
            .animation(jittering ? .linear(duration: 0.05).repeatForever()
                       : (mood == .drunk ? .easeInOut(duration: 1.5).repeatForever() : .default),
                       value: animate)
        }
        .scaleEffect(DojoProgress.companionScale(progress: progress), anchor: .bottom)
        .animation(.spring(duration: 0.6, bounce: 0.4), value: progress)
        // Gulp: runs once per logged drink, nothing in between.
        .keyframeAnimator(initialValue: 1.0, trigger: reaction) { content, stretch in
            content.scaleEffect(x: 2 - stretch, y: stretch, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(0.82, duration: 0.14)
                SpringKeyframe(1.14, duration: 0.18)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
        }
        .accessibilityHidden(true)
        // Every mood change (and each jitter burst) restarts all movements from
        // scratch: the drop is rebuilt (.id) and the trigger flips again.
        // Without this, a new mood's movement never started and the previous
        // one kept repeating, so moods mixed (bug found 27 Oct).
        .id(animationKey)
        // One run loop later: starting a repeating animation while a sheet or
        // pushed screen is still laying out repeats that layout move too.
        .onAppear { Task { @MainActor in moving = true } }
        .onChange(of: animationKey) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { moving = false }
            Task { @MainActor in moving = true }
        }
        .task(id: mood) {
            // Check twice a second whether a jitter burst is on; cheap, and only while hyper.
            guard mood == .hyper, animated, !reduceMotion else { jittering = false; return }
            while !Task.isCancelled {
                let burst = CompanionLogic.isJitterBurst(at: .now)
                if burst != jittering { jittering = burst }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var animationKey: String { "\(mood)-\(jittering)" }

    private var swayAngle: Double {
        switch mood {
        case .tipsy: 9
        case .drunk: 16
        default: 0
        }
    }

    private func wobble(w: Double) -> Double {
        if jittering { return (animate ? 1 : -1) * w * 0.025 }
        if mood == .drunk { return (animate ? 1 : -1) * w * 0.05 }
        return 0
    }

    private var eyeStyle: Eye.Style {
        switch mood {
        case .hyper: .wide
        case .tipsy: .sleepy
        case .drunk: .dizzy
        default: progress >= 1 ? .happy : .focused
        }
    }

    /// Stacked coloured bands with a moving wave on top. The wave is a wide strip
    /// that slides sideways forever (Core Animation), so nothing is redrawn.
    @ViewBuilder
    private func fill(w: Double, h: Double) -> some View {
        let bands = layers ?? (progress > 0 ? [FillLayer(tint: .water, fraction: min(progress, 1))] : [])
        let total = min(bands.reduce(0) { $0 + $1.fraction }, 1)
        ZStack(alignment: .topLeading) {
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                let bottom = bands.prefix(index).reduce(0) { $0 + $1.fraction }
                FillBand(from: bottom, to: min(bottom + band.fraction, 1), phase: 0, wavy: false)
                    .fill(band.tint.color.gradient)
            }
            if let top = bands.last, total > 0, total < 1 {
                WaveCrest()
                    .fill(top.tint.color)
                    .frame(width: w * 2, height: h * 0.05)
                    .offset(x: animate ? -w : 0, y: h * (1 - total) - h * 0.05 + 0.5)
                    .animation(.linear(duration: 2.5).repeatForever(autoreverses: false), value: animate)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    private func tails(w: Double, h: Double) -> some View {
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
                .rotationEffect(.degrees(Double(i == 0 ? 18 : 40) + (animate ? 6 : -6)), anchor: .leading)
                .animation(.easeInOut(duration: i == 0 ? 1.3 : 1.6).repeatForever(), value: animate)
                .offset(x: w * 0.62, y: h * 0.12)
        }
    }

    /// Little flexing arms for protein.
    private func arms(w: Double, h: Double) -> some View {
        ForEach([-1.0, 1.0], id: \.self) { side in
            ZStack(alignment: .top) {
                Capsule().fill(Dojo.water).frame(width: w * 0.14, height: h * 0.26)
                Circle().fill(Dojo.water).frame(width: w * 0.2, height: w * 0.2).offset(y: -h * 0.03)
            }
            .overlay(Capsule().stroke(Dojo.ink, lineWidth: 1.2).frame(width: w * 0.14, height: h * 0.26))
            .rotationEffect(.degrees(side * (animate ? 47 : 23)), anchor: .bottom)
            .animation(.easeInOut(duration: 0.7).repeatForever(), value: animate)
            .offset(x: side * w * 0.5, y: h * 0.18)
        }
    }

    private func speedLines(w: Double, h: Double) -> some View {
        ForEach(0..<3) { i in
            Capsule()
                .fill(Dojo.ink.opacity(0.35))
                .frame(width: w * (0.18 + 0.06 * Double(i % 2)), height: 2)
                .offset(x: -w * 0.62 + (animate ? 3 : -3), y: h * (0.0 + 0.12 * Double(i)))
                .animation(.linear(duration: 0.12).repeatForever(), value: animate)
        }
    }

    private func sparks(w: Double, h: Double) -> some View {
        ForEach(0..<3) { i in
            let angle = Double(i) * 2.1 + 0.6
            Image(systemName: "bolt.fill")
                .font(.system(size: w * 0.18))
                .foregroundStyle(.yellow)
                .opacity(animate ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.6 + Double(i) * 0.2).repeatForever(), value: animate)
                .offset(x: cos(angle) * w * 0.62, y: sin(angle) * h * 0.42 - h * 0.05)
        }
    }
}

/// One wavelength repeated twice across the width, so sliding it left by half
/// its width loops seamlessly.
nonisolated struct WaveCrest: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 48
        for step in 0...steps {
            let x = rect.minX + rect.width * Double(step) / Double(steps)
            let y = rect.midY + sin(Double(step) / Double(steps) * .pi * 4) * rect.height / 2
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Eye: View {
    enum Style { case focused, happy, wide, sleepy, dizzy }
    var style: Style
    var mirrored = false
    var color: Color = .white

    var body: some View {
        switch style {
        case .happy:
            HappyEyeShape()
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .wide:
            Circle().fill(color).scaleEffect(1.5)
        case .sleepy:
            Capsule().fill(color).scaleEffect(x: 1, y: 0.35).offset(y: 2)
        case .dizzy:
            // × eyes
            ZStack {
                Capsule().fill(color).frame(height: 2.5).rotationEffect(.degrees(40))
                Capsule().fill(color).frame(height: 2.5).rotationEffect(.degrees(-40))
            }
            .scaleEffect(0.8)
        case .focused:
            Capsule()
                .fill(color)
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
