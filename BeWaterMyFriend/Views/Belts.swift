import SwiftUI

/// Prestige seal: the 水 stamp from the app icon, coloured like the belt system
/// (★1 yellow, ★2 orange … ★7 black, then red-and-white and red).
struct PrestigeStamp: View {
    var level: Int

    var body: some View {
        let belt = Belt(rawValue: min(max(level, 1), Belt.allCases.count - 1)) ?? .yellow
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.18).fill(belt.color)
                RoundedRectangle(cornerRadius: s * 0.12)
                    .stroke(belt.isLight ? Color.black.opacity(0.6) : Color(red: 0.96, green: 0.94, blue: 0.89),
                            lineWidth: max(s * 0.05, 1))
                    .padding(s * 0.08)
                Text("水")
                    .font(.system(size: s * 0.6, weight: .semibold, design: .serif))
                    .foregroundStyle(belt.isLight ? Color.black.opacity(0.8) : Color(red: 0.96, green: 0.94, blue: 0.89))
            }
            .overlay(RoundedRectangle(cornerRadius: s * 0.18).stroke(belt.metalColor ?? .clear, lineWidth: 1.5))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Prestige \(level)")
    }
}

/// A small belt: plain colour, black with gold stripes for 1st–5th Dan,
/// red-and-white for 6th–8th Dan, red for 9th–10th Dan. Ranks that share a
/// belt colour get a bronze, silver or gold edge so they look different.
struct BeltBadge: View {
    var belt: Belt

    var body: some View {
        BeltPattern(belt: belt)
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

/// The belt's look as a fill: plain colour, gold Dan stripes (1st–5th),
/// or red-and-white blocks (6th–8th). Used for badges and the drop's mask.
struct BeltPattern: View {
    var belt: Belt

    var body: some View {
        GeometryReader { geo in
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
                    let stripe = max(geo.size.width * 0.03, 1.5)
                    HStack(spacing: stripe) {
                        ForEach(0..<level, id: \.self) { _ in
                            Rectangle().fill(belt.secondaryColor).frame(width: stripe)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, geo.size.width * 0.12)
                }
            }
        }
    }
}

extension Belt {
    /// Light belts need dark eyes on the mask.
    var isLight: Bool { self == .white || self == .yellow }

    /// Dark eyes on light belts and on the red-and-white 6th–8th Dan belts, where
    /// white eyes would vanish on the white blocks (user's call, 31 Oct).
    var eyeColor: Color {
        switch self {
        case .white, .yellow, .dan6, .dan7, .dan8: Color(white: 0.15)
        default: .white
        }
    }

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
