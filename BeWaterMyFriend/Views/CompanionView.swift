import SwiftUI

/// The ninja drop on the Today screen: fills up with today's drinks (in their
/// colours), reacts to what was drunk, wears its belt, and opens the dojo when tapped.
struct CompanionView: View {
    var progress: Double
    var layers: [FillLayer]
    var mood: CompanionMood
    /// Why the drop is in this mood, and until when (nil when calm).
    var reason: String? = nil
    var until: Date? = nil
    /// Increases with every logged drink: a short gulp reaction.
    var reaction: Int = 0
    var belt: Belt
    var prestige: Int
    var stats: DojoStats
    var goalDaysTowardBelt: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                NinjaDrop(progress: progress, belt: belt, layers: layers, mood: mood, prestige: prestige, reaction: reaction)
                    .frame(width: 64, height: 84)
                    // The headband tails reach ~20 pt past the drop on the right,
                    // arms and speed lines a little on the left: keep the text clear.
                    .padding(.leading, 6)
                    .padding(.trailing, 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.callout)
                    if let reason {
                        Text(until.map { "\(reason) · until \($0.formatted(date: .omitted, time: .shortened))" } ?? reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
