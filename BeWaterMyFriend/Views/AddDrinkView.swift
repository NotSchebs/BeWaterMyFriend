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
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { finish(onNew) } label: { Label("New drink", systemImage: "square.and.pencil") }
                    Button { finish(onScan) } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                }

                let results = DrinkSearch.results(query: search, presets: presets, entries: entries)
                Section(search.isEmpty ? "Your drinks" : "Results") {
                    if results.isEmpty {
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
}

/// Finds drinks the user already has: saved presets and past entries, one per
/// name + type + amount, best matches first.
enum DrinkSearch {
    struct Result: Identifiable {
        var id: String
        var draft: DrinkDraft
        var detail: String
    }

    static func results(query: String, presets: [DrinkPreset], entries: [DrinkEntry], limit: Int = 50) -> [Result] {
        let q = QuickLogRules.normalized(query)
        var seen = Set<String>()
        var out: [Result] = []

        func add(_ draft: DrinkDraft, detail: String) {
            let key = "\(QuickLogRules.normalized(draft.name))|\(draft.category.rawValue)|\(Int(draft.volumeML))"
            guard !seen.contains(key) else { return }
            guard q.isEmpty || QuickLogRules.normalized(draft.name).contains(q)
                    || draft.category.displayName.lowercased().contains(q) else { return }
            seen.insert(key)
            out.append(Result(id: key, draft: draft, detail: detail))
        }

        for preset in presets {
            add(DrinkDraft(preset: preset), detail: preset.isInQuickLog ? "In Quick log" : "Saved")
        }
        for entry in entries {
            var draft = DrinkDraft(entry: entry)
            draft.source = entry.source
            draft.barcode = entry.barcode
            add(draft, detail: "Last: \(entry.timestamp.formatted(date: .abbreviated, time: .omitted))")
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
