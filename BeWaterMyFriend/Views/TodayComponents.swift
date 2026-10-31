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

private final class TileFrames {
    var frames: [PersistentIdentifier: CGRect] = [:]
}

struct QuickLogGrid: View {
    var presets: [DrinkPreset]
    /// All presets, also those not in the grid: stars are numbered across all of them.
    var allPresets: [DrinkPreset]
    /// The tile that was just tapped, shown with a checkmark for a moment.
    var flashed: PersistentIdentifier? = nil
    /// Edit mode, like rearranging the iPhone home screen: tiles wiggle, a minus
    /// removes one, dragging moves it, "+" adds one. Entered with a long press.
    @Binding var isEditing: Bool
    var onTap: (DrinkPreset) -> Void
    var onMove: (DrinkPreset, DrinkPreset) -> Void = { _, _ in }
    var onRemove: (DrinkPreset) -> Void = { _ in }
    var onAdd: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false
    /// Where every tile sits, to know which one the finger is over. In a plain
    /// object, not @State: as state, every measurement redrew the grid, which was
    /// measured again, and the app ran at 100 % CPU in edit mode (31 Oct).
    @State private var tileFrames = TileFrames()
    @State private var draggedID: PersistentIdentifier?
    /// The dragged tile's centre, following the finger.
    @State private var dragCenter: CGPoint = .zero
    /// Where on the tile the finger picked it up.
    @State private var grabOffset: CGSize = .zero
    @GestureState private var isDragActive = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        if presets.isEmpty && !isEditing {
            VStack(spacing: 10) {
                Text("Your Quick log is empty.")
                    .foregroundStyle(.secondary)
                Button("Add drinks", systemImage: "plus") {
                    isEditing = true
                    onAdd()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(presets.enumerated()), id: \.element.persistentModelID) { index, preset in
                    Group {
                        if isEditing {
                            editTile(preset, index: index)
                        } else {
                            // Tap and long press instead of a Button: a Button would
                            // also log the drink when the long press is released.
                            tile(preset)
                                .contentShape(.rect(cornerRadius: 14))
                                .onTapGesture { onTap(preset) }
                                .onLongPressGesture(minimumDuration: 0.5) { isEditing = true }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Log \(preset.name), \(Format.ml(preset.volumeML))")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { onTap(preset) }
                                .accessibilityAction(named: "Edit Quick log") { isEditing = true }
                        }
                    }
                }
                if isEditing && !QuickLogRules.isFull(presets) {
                    Button(action: onAdd) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                            Text("Add")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a drink to the Quick log")
                }
            }
            .coordinateSpace(.named(Self.gridSpace))
            .sensoryFeedback(.impact, trigger: isEditing) { _, editing in editing }
            .sensoryFeedback(.selection, trigger: draggedID) { _, id in id != nil }
            // The gesture was cancelled (e.g. a call came in): put the tile down.
            .onChange(of: isDragActive) { _, active in
                if !active { endDrag() }
            }
            // The wiggle only runs in edit mode, so it costs nothing otherwise.
            .onChange(of: isEditing, initial: true) { _, editing in
                // One run loop later: see NinjaDrop (repeating animations and layout).
                Task { @MainActor in wiggle = editing && !reduceMotion }
            }
        }
    }

    /// `nonisolated`: `onGeometryChange` reads it off the main thread.
    nonisolated private static let gridSpace = "quickLogGrid"

    private func editTile(_ preset: DrinkPreset, index: Int) -> some View {
        let id = preset.persistentModelID
        let isDragged = draggedID == id
        let frame = tileFrames.frames[id] ?? .zero
        return tile(preset)
            .overlay(alignment: .topLeading) {
                Button { onRemove(preset) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.red)
                        // A bigger target than the icon.
                        .padding(6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .offset(x: -10, y: -10)
                .accessibilityLabel("Remove \(preset.name) from the Quick log")
            }
            .overlay(alignment: .topTrailing) {
                StarControl(preset: preset, presets: allPresets)
                    .font(.caption)
                    .padding(6)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.gridSpace)) } action: { tileFrames.frames[id] = $0 }
            .rotationEffect(.degrees(!isDragged && wiggle ? (index.isMultiple(of: 2) ? 1.3 : -1.3) : 0))
            .animation(wiggle ? .easeInOut(duration: 0.14).repeatForever() : .default, value: wiggle)
            .scaleEffect(isDragged ? 1.1 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.2 : 0), radius: 8, y: 4)
            .offset(isDragged ? CGSize(width: dragCenter.x - frame.midX, height: dragCenter.y - frame.midY) : .zero)
            .zIndex(isDragged ? 1 : 0)
            .contentShape(.rect(cornerRadius: 14))
            // Hold briefly, then drag. A quick swipe on a tile still scrolls the page.
            .gesture(LongPressGesture(minimumDuration: 0.15)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.gridSpace)))
                .updating($isDragActive) { value, active, _ in
                    if case .second = value { active = true }
                }
                .onChanged { value in
                    guard case .second(true, let drag?) = value else { return }
                    dragChanged(preset, drag: drag)
                }
                .onEnded { _ in endDrag() })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quickLogEdit-\(preset.name)")
            .accessibilityAction(named: "Move earlier") {
                if index > 0 { onMove(preset, presets[index - 1]) }
            }
            .accessibilityAction(named: "Move later") {
                if index < presets.count - 1 { onMove(preset, presets[index + 1]) }
            }
    }

    private func dragChanged(_ preset: DrinkPreset, drag: DragGesture.Value) {
        let id = preset.persistentModelID
        if draggedID != id {
            let frame = tileFrames.frames[id] ?? .zero
            grabOffset = CGSize(width: drag.startLocation.x - frame.midX, height: drag.startLocation.y - frame.midY)
            draggedID = id
        }
        dragCenter = CGPoint(x: drag.location.x - grabOffset.width, y: drag.location.y - grabOffset.height)
        // Over another tile: take its place, the others make room.
        if let target = presets.first(where: { $0.persistentModelID != id
            && tileFrames.frames[$0.persistentModelID]?.insetBy(dx: 12, dy: 12).contains(dragCenter) == true }) {
            // The dragged tile lands in the target's slot; the finger position is
            // measured from there right away, so it doesn't jump.
            tileFrames.frames[id] = tileFrames.frames[target.persistentModelID]
            withAnimation(.spring(duration: 0.3)) { onMove(preset, target) }
        }
    }

    private func endDrag() {
        guard draggedID != nil else { return }
        withAnimation(.spring(duration: 0.3)) { draggedID = nil }
    }

    private func tile(_ preset: DrinkPreset) -> some View {
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
            if !isEditing, let number = preset.starNumber {
                StarBadge(number: number)
                    .font(.caption2)
                    .padding(6)
            }
        }
    }
}

/// ★1, ★2 or ★3.
struct StarBadge: View {
    var number: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("\(number)")
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        }
    }
}

/// Picks a drink's widget star. No star yet: a tap gives it the next free number.
/// Already starred, or all three taken: a tap opens a menu with the numbers.
struct StarControl: View {
    var preset: DrinkPreset
    var presets: [DrinkPreset]
    @Environment(\.modelContext) private var context

    var body: some View {
        let starred = DrinkStars.starred(presets)
        Group {
            if preset.starNumber == nil && starred.count < DrinkStars.maxStars {
                Button {
                    change { DrinkStars.star(preset, in: presets) }
                } label: {
                    Image(systemName: "star")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Star \(preset.name) for the widgets")
            } else {
                Menu {
                    menuItems(starred)
                } label: {
                    if let number = preset.starNumber {
                        StarBadge(number: number)
                    } else {
                        Image(systemName: "star")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(preset.starNumber.map { "\(preset.name), star \($0). Change" }
                                    ?? "Star \(preset.name) instead of another drink")
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func menuItems(_ starred: [DrinkPreset]) -> some View {
        if preset.starNumber != nil {
            ForEach(starred.indices, id: \.self) { index in
                let number = index + 1
                Button {
                    change { DrinkStars.assign(preset, number: number, in: presets) }
                } label: {
                    if starred[index] === preset {
                        Label("★\(number)", systemImage: "checkmark")
                    } else {
                        Text("★\(number) (swap with \(starred[index].name))")
                    }
                }
                .disabled(starred[index] === preset)
            }
            Button("Remove star", role: .destructive) {
                change { DrinkStars.unstar(preset, in: presets) }
            }
        } else {
            Section("Replace a star") {
                ForEach(starred.indices, id: \.self) { index in
                    Button("★\(index + 1): \(starred[index].name)") {
                        change { DrinkStars.assign(preset, number: index + 1, in: presets) }
                    }
                }
            }
        }
    }

    private func change(_ action: () -> Void) {
        action()
        try? context.save()
    }
}

/// "+" in the Quick log edit mode: every drink ever logged or saved that isn't in
/// the Quick log yet. Tapping one adds it and returns to the edit mode.
struct AddToQuickLogView: View {
    var presets: [DrinkPreset]
    var onPick: (DrinkDraft) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Read once when the sheet opens, not with @Query: the full history is only
    /// needed here, and each drink only once (see `DrinkSearch`).
    @State private var allDrinks: [DrinkSearch.Result]?
    @State private var search = ""

    private var results: [DrinkSearch.Result] {
        let query = QuickLogRules.normalized(search)
        return (allDrinks ?? []).filter { result in
            guard QuickLogRules.matching(result.draft, in: presets)?.isInQuickLog != true else { return false }
            return query.isEmpty || QuickLogRules.normalized(result.draft.name).contains(query)
                || result.draft.category.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let results = results
                if allDrinks != nil && results.isEmpty {
                    Text(search.isEmpty ? "All your drinks are already in the Quick log." : "No drink called \"\(search)\" yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        onPick(result.draft)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.draft.category.symbolName)
                                .foregroundStyle(result.draft.category.isAlcoholic ? .orange : Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.draft.name)
                                Text(result.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.ml(result.draft.volumeML))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search drinks")
            .dojoBackground()
            .navigationTitle("Add to Quick log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                allDrinks = DrinkSearch.results(query: "", presets: presets, entries: DrinkSearch.allEntries(in: context), limit: .max)
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
