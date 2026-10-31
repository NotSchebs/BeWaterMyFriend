import SwiftData
import SwiftUI

/// Opened with +: search your saved and past drinks, or start a new one or a scan.
/// Picking a drink opens the editor pre-filled, so the amount can be checked
/// before saving (no accidental logs).
struct AddDrinkView: View {
    var onPick: (DrinkDraft) -> Void
    var onNew: () -> Void
    var onScan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\DrinkPreset.sortOrder), SortDescriptor(\DrinkPreset.name)]) private var presets: [DrinkPreset]
    /// The 500 most recent drinks are plenty for "drinks you had before" (performance).
    @Query(Self.recentDrinks) private var entries: [DrinkEntry]

    static var recentDrinks: FetchDescriptor<DrinkEntry> {
        var d = FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        d.fetchLimit = 500
        return d
    }
    @State private var search = ""
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0

    var body: some View {
        NavigationStack {
            let results = DrinkSearch.results(query: search, presets: presets, entries: entries)
            List {
                if companionEnabled {
                    Section {
                        AddDrinkCompanion(query: search.trimmingCharacters(in: .whitespaces), hasResults: !results.isEmpty,
                                          usual: search.isEmpty ? DrinkSuggestion.usual(entries: entries, now: .now, calendar: .current) : nil,
                                          belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)),
                                          onPick: { pick(Self.draft(from: $0)) })
                    }
                }
                Section {
                    Button { finish(onNew) } label: { Label("New drink", systemImage: "square.and.pencil") }
                    Button { finish(onScan) } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                }

                Section(search.isEmpty ? "Your drinks" : "Results") {
                    // While searching, the drop already says nothing matched.
                    if results.isEmpty && (search.isEmpty || !companionEnabled) {
                        Text(search.isEmpty ? "Drinks you save or log show up here." : "No drink called \"\(search)\" yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        Button {
                            var draft = result.draft
                            draft.timestamp = .now
                            pick(draft)
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
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search drinks")
            .dojoBackground()
            .navigationTitle("Add drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func finish(_ action: @escaping () -> Void) {
        dismiss()
        action()
    }

    private func pick(_ draft: DrinkDraft) {
        dismiss()
        onPick(draft)
    }

    /// A past drink as a new draft for now.
    static func draft(from entry: DrinkEntry) -> DrinkDraft {
        var draft = DrinkDraft(entry: entry)
        draft.source = entry.source
        draft.barcode = entry.barcode
        draft.timestamp = .now
        return draft
    }
}

/// The drop on the Add drink screen. Idle, it suggests the drink you usually
/// have around this time (tap it to log); while you search it sweeps its
/// magnifying glass, and shrugs when nothing matches.
struct AddDrinkCompanion: View {
    var query: String
    var hasResults: Bool
    var usual: DrinkEntry?
    var belt: Belt
    var onPick: (DrinkEntry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    private enum Phase { case idle, searching, notFound }

    private var phase: Phase {
        if query.isEmpty { return .idle }
        return hasResults ? .searching : .notFound
    }

    var body: some View {
        let seed = CompanionLines.daySeed(.now, calendar: .current)
        HStack(spacing: 10) {
            ZStack {
                NinjaDrop(progress: 0.55, belt: belt,
                          layers: usual.map { [FillLayer(tint: $0.category.tint, fraction: 0.55)] },
                          mood: phase == .idle ? (usual.map { CompanionLogic.mood(for: $0.category.tint) } ?? .calm) : .calm)
                    .frame(width: 44, height: 58)
                    .rotationEffect(.degrees(phase == .notFound ? -12 : 0), anchor: .bottom)
                if phase == .searching {
                    MagnifyingGlass()
                        .frame(width: 26, height: 26)
                        .rotationEffect(.degrees(sweeping ? 10 : -10))
                        .offset(x: sweeping ? 14 : -6, y: sweeping ? 13 : 9)
                        .animation(.easeInOut(duration: 1.3).repeatForever(), value: sweeping)
                        .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity))
                } else if phase == .notFound {
                    Image(systemName: "questionmark")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                        .offset(x: 30, y: -24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: phase)
            .padding(.leading, 4)
            .padding(.trailing, 16)

            SpeechBubble(text: text(seed: seed))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        // Tapping the drop or its bubble logs the usual drink (via the editor, as always).
        .onTapGesture { if phase == .idle, let usual { onPick(usual) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(phase == .idle && usual != nil ? .isButton : [])
        // Started one run loop after appearing (see ScanCompanion: avoids the jumping drop).
        .onAppear { Task { @MainActor in sweeping = !reduceMotion } }
    }

    private func text(seed: Int) -> String {
        switch phase {
        case .idle:
            guard let usual else { return CompanionLines.addIdle(seed: seed) }
            return CompanionLines.addSuggestion(name: usual.name, ml: usual.volumeML, seed: seed)
        case .searching: return CompanionLines.addSearching(query)
        case .notFound: return CompanionLines.addNotFound(query)
        }
    }
}

/// Finds drinks the user already has: saved presets and past entries, one per
/// name + type + amount, best matches first.
enum DrinkSearch {
    struct Result: Identifiable {
        var id: String
        var draft: DrinkDraft
        var detail: String
    }

    /// The whole history, newest first, loading only what's needed to tell drinks
    /// apart (performance). The rest of a drink loads when it's actually used.
    static func allEntries(in context: ModelContext) -> [DrinkEntry] {
        var descriptor = FetchDescriptor<DrinkEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.propertiesToFetch = [\.name, \.categoryRaw, \.volumeML, \.timestamp]
        return (try? context.fetch(descriptor)) ?? []
    }

    static func results(query: String, presets: [DrinkPreset], entries: [DrinkEntry], limit: Int = 50) -> [Result] {
        let q = QuickLogRules.normalized(query)
        var seen = Set<String>()
        var out: [Result] = []

        func key(_ name: String, _ category: DrinkCategory, _ ml: Double) -> String {
            "\(QuickLogRules.normalized(name))|\(category.rawValue)|\(Int(ml))"
        }
        func matches(_ name: String, _ category: DrinkCategory) -> Bool {
            q.isEmpty || QuickLogRules.normalized(name).contains(q) || category.displayName.lowercased().contains(q)
        }

        for preset in presets {
            let id = key(preset.name, preset.category, preset.volumeML)
            guard !seen.contains(id), matches(preset.name, preset.category) else { continue }
            seen.insert(id)
            out.append(Result(id: id, draft: DrinkDraft(preset: preset), detail: preset.isInQuickLog ? "In Quick log" : "Saved"))
        }
        for entry in entries {
            let id = key(entry.name, entry.category, entry.volumeML)
            // Checked before building the draft: decoding nutrients for every
            // repeat of the same drink would be slow with years of history.
            guard !seen.contains(id), matches(entry.name, entry.category) else { continue }
            seen.insert(id)
            var draft = DrinkDraft(entry: entry)
            draft.source = entry.source
            draft.barcode = entry.barcode
            out.append(Result(id: id, draft: draft, detail: "Last: \(entry.timestamp.formatted(date: .abbreviated, time: .omitted))"))
        }
        if !q.isEmpty {
            // Names starting with the query first.
            out.sort { a, b in
                let aStarts = QuickLogRules.normalized(a.draft.name).hasPrefix(q)
                let bStarts = QuickLogRules.normalized(b.draft.name).hasPrefix(q)
                return aStarts && !bStarts
            }
        }
        return Array(out.prefix(limit))
    }
}
