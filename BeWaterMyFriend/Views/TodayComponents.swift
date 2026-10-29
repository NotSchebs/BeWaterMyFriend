import SwiftData
import SwiftUI

// Small pieces of the Today screen (legend, tiles, Quick log, toast, rows).
// StatTile and EntryRow are also used by History and Stats.

/// What each colour in the ring and the drop means, with today's amount.
struct ColorLegend: View {
    var totals: [TintTotal]
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Two columns normally; one with very large text, so names aren't cut off.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(totals, id: \.tint) { total in
                HStack(spacing: 6) {
                    Circle()
                        .fill(total.tint.ringColor)
                        .frame(width: 10, height: 10)
                    Text(total.tint.displayName)
                        .font(.caption)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    Text(Format.ml(total.ml))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Three tiles side by side, or stacked when the text is very large.
struct StatTileRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout())
        layout { content }
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var symbol: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // One line per tile when stacked: icon and title left, value right.
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct QuickLogGrid: View {
    var presets: [DrinkPreset]
    /// The tile that was just tapped, shown with a checkmark for a moment.
    var flashed: PersistentIdentifier? = nil
    var onTap: (DrinkPreset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        if presets.isEmpty {
            Text("No presets. Add some in Settings.")
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(presets) { preset in
                    Button {
                        onTap(preset)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.category.symbolName)
                                .font(.title3)
                                .foregroundStyle(preset.category.isAlcoholic ? .orange : Color.accentColor)
                            Text(preset.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(Format.ml(preset.volumeML))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(6)
                        .background(flashed == preset.persistentModelID ? Color.green.opacity(0.25) : Color.accentColor.opacity(0.1),
                                    in: .rect(cornerRadius: 14))
                        .overlay {
                            if flashed == preset.persistentModelID {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .scaleEffect(flashed == preset.persistentModelID ? 0.96 : 1)
                        .animation(.spring(duration: 0.3), value: flashed)
                        .overlay(alignment: .topTrailing) {
                            if preset.isFavourite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(preset.name), \(Format.ml(preset.volumeML))")
                }
            }
        }
    }
}

/// Confirmation after a quick log, with Undo.
struct LoggedToast: View {
    var entry: DrinkEntry
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Logged \(entry.name) · \(Format.ml(entry.volumeML))")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

struct EntryRow: View {
    var entry: DrinkEntry
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.symbolName)
                .foregroundStyle(entry.category.isAlcoholic ? .orange : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.ml(entry.volumeML))
                .font(.subheadline.monospacedDigit())
        }
        .contentShape(.rect)
    }

    private var details: String {
        var parts = [showsDate
            ? entry.timestamp.formatted(date: .abbreviated, time: .shortened)
            : entry.timestamp.formatted(date: .omitted, time: .shortened)]
        if entry.caffeineMg > 0 { parts.append(Format.mg(entry.caffeineMg) + " caffeine") }
        if let abv = entry.alcoholPercent, abv > 0 { parts.append("\(abv.formatted()) % alc.") }
        return parts.joined(separator: " · ")
    }
}
