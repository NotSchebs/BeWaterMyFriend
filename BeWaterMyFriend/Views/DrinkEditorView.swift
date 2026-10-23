import SwiftData
import SwiftUI

/// What the editor is creating or changing.
enum EditorMode: Identifiable {
    case newEntry
    case editEntry(DrinkEntry)
    case newPreset
    case editPreset(DrinkPreset)

    var id: String {
        switch self {
        case .newEntry: "newEntry"
        case .editEntry(let entry): "entry-\(entry.persistentModelID.hashValue)"
        case .newPreset: "newPreset"
        case .editPreset(let preset): "preset-\(preset.persistentModelID.hashValue)"
        }
    }

    var isPreset: Bool {
        switch self {
        case .newPreset, .editPreset: true
        default: false
        }
    }

    var isNew: Bool {
        switch self {
        case .newEntry, .newPreset: true
        default: false
        }
    }
}

/// One form for entries and presets. Works on a `DrinkDraft` copy, so Cancel
/// discards everything and only Save writes to the database.
struct DrinkEditorView: View {
    let mode: EditorMode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DrinkDraft
    @State private var confirmDelete = false

    init(mode: EditorMode) {
        self.mode = mode
        switch mode {
        case .newEntry, .newPreset: _draft = State(initialValue: DrinkDraft())
        case .editEntry(let entry): _draft = State(initialValue: DrinkDraft(entry: entry))
        case .editPreset(let preset): _draft = State(initialValue: DrinkDraft(preset: preset))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Rivella Rot", text: $draft.name)
                    Picker("Type", selection: $draft.category) {
                        ForEach(DrinkCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.symbolName).tag(category)
                        }
                    }
                    LabeledContent("Amount") {
                        HStack {
                            TextField("ml", value: $draft.volumeML, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("ml").foregroundStyle(.secondary)
                        }
                    }
                    if mode.isPreset {
                        Toggle("Favourite", isOn: $draft.isFavourite)
                    } else {
                        DatePicker("Time", selection: $draft.timestamp, in: ...Date.now)
                    }
                }

                hydrationSection

                if draft.category.isAlcoholic {
                    Section("Alcohol") {
                        LabeledContent("Alcohol by volume") {
                            HStack {
                                TextField("e.g. 5", value: $draft.alcoholPercent, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                        let grams = DrinkMath.alcoholGrams(volumeML: draft.volumeML, alcoholPercent: draft.alcoholPercent)
                        if grams > 0 {
                            LabeledContent("Estimated",
                                           value: "\(Format.amount(grams, unit: "g")) · \(Format.standardDrinks(DrinkMath.standardDrinks(alcoholGrams: grams))) std drinks")
                        }
                    }
                }

                nutrientSections

                if !mode.isNew {
                    Section {
                        Button(mode.isPreset ? "Delete preset" : "Delete drink", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .dojoBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.isValid)
                }
            }
            .confirmationDialog("Delete this \(mode.isPreset ? "preset" : "drink")?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    private var hydrationSection: some View {
        Section {
            Toggle("Automatic", isOn: Binding(
                get: { draft.hydrationPercent == nil },
                set: { draft.hydrationPercent = $0 ? nil : draft.automaticHydrationPercent }
            ))
            if let percent = draft.hydrationPercent {
                Slider(value: Binding(get: { percent }, set: { draft.hydrationPercent = $0 }),
                       in: 0...100, step: 5)
            }
            LabeledContent("Counts toward goal",
                           value: "\(Format.percent(draft.effectiveHydrationPercent / 100)) · \(Format.ml(DrinkMath.hydrationML(volumeML: draft.volumeML, percent: draft.effectiveHydrationPercent)))")
        } header: {
            Text("Water goal")
        } footer: {
            Text(draft.category.isAlcoholic
                 ? "Automatic counts the non-alcohol part of the drink (a 5 % beer counts 95 %). An estimate, not medical advice."
                 : "Automatic counts the whole drink. Lower it if you want this drink to count less.")
        }
    }

    @ViewBuilder
    private var nutrientSections: some View {
        ForEach(Nutrient.Group.allCases, id: \.self) { group in
            Section {
                DisclosureGroup(group.rawValue) {
                    ForEach(Nutrient.allCases.filter { $0.group == group }) { nutrient in
                        NutrientField(nutrient: nutrient,
                                      value: $draft.nutrientsPer100ml[nutrient],
                                      volumeML: draft.volumeML)
                    }
                }
            } footer: {
                if group == Nutrient.Group.allCases.last {
                    Text("Values per 100 ml. Leave empty if unknown. All values are estimates.")
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .newEntry: "New drink"
        case .editEntry: "Edit drink"
        case .newPreset: "New preset"
        case .editPreset: "Edit preset"
        }
    }

    private func save() {
        switch mode {
        case .newEntry:
            context.insert(draft.makeEntry())
        case .editEntry(let entry):
            draft.apply(to: entry)
        case .newPreset:
            let count = (try? context.fetchCount(FetchDescriptor<DrinkPreset>())) ?? 0
            context.insert(draft.makePreset(sortOrder: count))
        case .editPreset(let preset):
            draft.apply(to: preset)
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        switch mode {
        case .editEntry(let entry): EntryActions.delete([entry], in: context)
        case .editPreset(let preset):
            context.delete(preset)
            try? context.save()
        default: break
        }
        dismiss()
    }
}

/// Input for one nutrient per 100 ml, showing the total for the current amount.
struct NutrientField: View {
    let nutrient: Nutrient
    @Binding var value: Double?
    let volumeML: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(nutrient.displayName)
                if let total = DrinkMath.scale(value, toVolumeML: volumeML) {
                    Text("\(Format.amount(total, unit: nutrient.unit)) in \(Format.ml(volumeML))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("–", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(nutrient.unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }
}

#Preview {
    DrinkEditorView(mode: .newEntry)
        .modelContainer(PreviewData.container)
}
