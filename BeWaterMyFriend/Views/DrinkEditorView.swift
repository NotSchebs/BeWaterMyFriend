import SwiftData
import SwiftUI

/// What the editor is creating or changing.
enum EditorMode: Identifiable {
    case newEntry
    case editEntry(DrinkEntry)
    case newPreset
    case editPreset(DrinkPreset)
    /// A new entry pre-filled from a barcode scan, shown for review.
    case scanned(DrinkDraft)
    /// A new entry pre-filled from one of the user's drinks (search).
    case prefilled(DrinkDraft)

    var id: String {
        switch self {
        case .newEntry: "newEntry"
        case .editEntry(let entry): "entry-\(entry.persistentModelID.hashValue)"
        case .newPreset: "newPreset"
        case .editPreset(let preset): "preset-\(preset.persistentModelID.hashValue)"
        case .scanned(let draft): "scan-\(draft.barcode ?? "")"
        case .prefilled(let draft): "prefilled-\(draft.name)-\(draft.volumeML)"
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
        case .newEntry, .newPreset, .scanned, .prefilled: true
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
    @State private var askQuickLog = false
    @Query private var presets: [DrinkPreset]
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0
    @AppStorage(SettingsKey.prestigeLevel) private var prestigeLevel = 0
    /// Drinks of the last few hours, for the mood preview (no full history).
    @Query(filter: DrinkEditorView.recentFilter()) private var recentEntries: [DrinkEntry]

    private static func recentFilter() -> Predicate<DrinkEntry> {
        let since = Date.now.addingTimeInterval(-4 * 3600)
        return #Predicate { $0.timestamp >= since }
    }

    init(mode: EditorMode) {
        self.mode = mode
        switch mode {
        case .newEntry, .newPreset: _draft = State(initialValue: DrinkDraft())
        case .editEntry(let entry): _draft = State(initialValue: DrinkDraft(entry: entry))
        case .editPreset(let preset): _draft = State(initialValue: DrinkDraft(preset: preset))
        case .scanned(let scanned), .prefilled(let scanned): _draft = State(initialValue: scanned)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if companionEnabled && !mode.isPreset {
                    Section { preview }
                }

                if let note = draft.scanNote {
                    Section {
                        Label(note, systemImage: "barcode.viewfinder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Name, e.g. Rivella Rot", text: $draft.name)
                    Picker("Type", selection: $draft.category) {
                        ForEach(DrinkCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.symbolName).tag(category)
                        }
                    }
                    if draft.category.isPowderMix {
                        LabeledContent("Powder") {
                            HStack {
                                TextField("g", value: Binding(
                                    get: { draft.effectivePowderGrams },
                                    set: { draft.powderGrams = $0 }
                                ), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text("g").foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent(draft.category.isPowderMix ? "Mixed with" : "Amount") {
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
                        DatePicker("Time", selection: $draft.timestamp, in: timeRange)
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
            .onChange(of: draft.category) { old, new in
                // Switching to a powder drink: start from a typical scoop and glass.
                if new.isPowderMix && !old.isPowderMix {
                    draft.powderGrams = draft.powderGrams ?? new.typicalPowderGrams
                    draft.volumeML = new.typicalLiquidML
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { trySave() }
                        .disabled(!draft.isValid)
                }
            }
            .alert(QuickLogRules.isFull(presets) ? "Save \(trimmedName) for later?" : "Add \(trimmedName) to Quick log?",
                   isPresented: $askQuickLog) {
                Button(QuickLogRules.isFull(presets) ? "Save" : "Add to Quick log") { save(addToQuickLog: true) }
                Button("Not now", role: .cancel) { save(addToQuickLog: false) }
            } message: {
                Text(QuickLogRules.isFull(presets)
                     ? "Your Quick log is full (\(QuickLogRules.maxItems) drinks). It will be in search and under Settings › Presets, where you can swap it into the Quick log."
                     : "Then it's one tap next time.")
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
                                      base: draft.nutrientBase,
                                      baseUnit: draft.category.isPowderMix ? "g" : "ml")
                    }
                }
            } footer: {
                if group == Nutrient.Group.allCases.last {
                    Text(draft.category.isPowderMix
                         ? "Values per 100 g of powder, as on the package. Leave empty if unknown. All values are estimates."
                         : "Values per 100 ml. Leave empty if unknown. All values are estimates.")
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .newEntry: "New drink"
        case .scanned: "Scanned drink"
        case .prefilled: "New drink"
        case .editEntry: "Edit drink"
        case .newPreset: "New preset"
        case .editPreset: "Edit preset"
        }
    }

    /// The drop previews this drink: its colour, and the mood it would cause.
    private var preview: some View {
        let editing: DrinkEntry? = if case .editEntry(let entry) = mode { entry } else { nil }
        let others = recentEntries.filter { $0.persistentModelID != editing?.persistentModelID }
        let now = Date.now
        let before = CompanionLogic.moodState(entries: others, now: now).mood
        let after = CompanionLogic.moodState(entries: others + [draft.makeEntry()], now: now).mood
        let belt = Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0))
        let ml = DrinkMath.hydrationML(volumeML: draft.volumeML, percent: draft.effectiveHydrationPercent)
        return HStack(spacing: 16) {
            NinjaDrop(progress: 0.55, belt: belt, layers: [FillLayer(tint: draft.category.tint, fraction: 0.55)],
                      mood: after, prestige: prestigeLevel)
                .frame(width: 44, height: 58)
                .padding(.trailing, 12)
            Text(Self.previewText(before: before, after: after, ml: ml))
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    static func previewText(before: CompanionMood, after: CompanionMood, ml: Double) -> String {
        guard after != before else {
            return ml > 0 ? "This adds \(Format.ml(ml)) toward your goal." : "This won't count toward your goal."
        }
        switch after {
        case .drunk: return "Whoa, this would make me properly drunk. Maybe a water first?"
        case .tipsy: return "This will make me a bit tipsy."
        case .hyper: return "Caffeine! This will make me hyper."
        case .strong: return "Protein! Time to flex."
        case .charged: return "Electrolytes! I'll be fully charged."
        case .calm: return "This adds \(Format.ml(ml)) toward your goal."
        }
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespaces) }

    /// Drinks can be logged for today and the two days before, not earlier.
    private var timeRange: ClosedRange<Date> {
        let existing: Date? = if case .editEntry(let entry) = mode { entry.timestamp } else { nil }
        return LogTimeLimit.range(now: .now, boundary: DayBoundary(dayEndMinutes: dayEndMinutes), existing: existing)
    }

    /// New drinks that aren't saved yet: ask whether to add them to the Quick log.
    private func trySave() {
        let isNewDrink: Bool = switch mode {
        case .newEntry, .scanned, .prefilled: true
        default: false
        }
        let known = QuickLogRules.existingPreset(barcode: draft.barcode, name: draft.name,
                                                 category: draft.category, in: presets)
        if isNewDrink && known == nil {
            askQuickLog = true
        } else {
            save(addToQuickLog: false)
        }
    }

    private func save(addToQuickLog: Bool) {
        let full = QuickLogRules.isFull(presets)
        switch mode {
        case .newEntry, .prefilled:
            context.insert(draft.makeEntry())
            if addToQuickLog {
                let preset = draft.makePreset(sortOrder: presets.count)
                preset.isInQuickLog = !full
                context.insert(preset)
            }
        case .editEntry(let entry):
            draft.apply(to: entry)
        case .newPreset:
            let preset = draft.makePreset(sortOrder: presets.count)
            preset.isInQuickLog = !full
            context.insert(preset)
        case .editPreset(let preset):
            draft.apply(to: preset)
        case .scanned:
            context.insert(draft.makeEntry())
            // Always remember scans (corrections are reused for the barcode);
            // only shown in the Quick log if the user said so.
            rememberScannedPreset(showInQuickLog: addToQuickLog && !full)
        }
        try? context.save()
        dismiss()
    }

    /// Updates the preset with this barcode, or creates one, so the user's
    /// corrections are used the next time this product is scanned.
    private func rememberScannedPreset(showInQuickLog: Bool) {
        guard let barcode = draft.barcode else { return }
        let code: String? = barcode
        let existing = try? context.fetch(FetchDescriptor<DrinkPreset>(predicate: #Predicate { $0.barcode == code })).first
        if let existing {
            var updated = draft
            updated.isFavourite = existing.isFavourite
            updated.apply(to: existing)
        } else {
            let preset = draft.makePreset(sortOrder: presets.count)
            preset.isInQuickLog = showInQuickLog
            context.insert(preset)
        }
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
    /// ml of drink, or g of powder for powder drinks.
    let base: Double
    let baseUnit: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(nutrient.displayName)
                if let total = DrinkMath.scale(value, toVolumeML: base) {
                    Text("\(Format.amount(total, unit: nutrient.unit)) in \(Format.amount(base, unit: baseUnit))")
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
