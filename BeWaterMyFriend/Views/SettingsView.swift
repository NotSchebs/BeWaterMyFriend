import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goalML, in: 500...6000, step: 250) {
                        LabeledContent("Daily water goal", value: Format.ml(goalML))
                    }
                } footer: {
                    Text("An estimate, not medical advice. Choose what fits you.")
                }

                Section {
                    Picker("Day ends at", selection: $dayEndMinutes) {
                        ForEach(Array(stride(from: 0, through: 6 * 60, by: 30)), id: \.self) { minutes in
                            Text(timeLabel(minutes)).tag(minutes)
                        }
                    }
                } footer: {
                    Text("Drinks before this time count for the previous day. Useful if you go to bed after midnight.")
                }

                Section {
                    Toggle("Ninja drop companion", isOn: $companionEnabled)
                } footer: {
                    Text("A playful companion on the Today screen. It never dies or loses progress.")
                }

                Section {
                    NavigationLink("Drink presets") {
                        PresetListView()
                    }
                }

                Section("About") {
                    Text("BeWaterMyFriend tracks water, caffeine, alcohol and nutrients. All values are estimates, not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func timeLabel(_ minutes: Int) -> String {
        let comps = DateComponents(hour: minutes / 60, minute: minutes % 60)
        let date = Calendar.current.date(from: comps) ?? .now
        let label = date.formatted(date: .omitted, time: .shortened)
        return minutes == 0 ? "\(label) (midnight)" : label
    }
}

struct PresetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\DrinkPreset.sortOrder), SortDescriptor(\DrinkPreset.name)])
    private var presets: [DrinkPreset]
    @State private var editor: EditorMode?

    var body: some View {
        List {
            ForEach(presets) { preset in
                HStack {
                    Button {
                        editor = .editPreset(preset)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preset.category.symbolName)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                Text("\(preset.category.displayName) · \(Format.ml(preset.volumeML))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .tint(.primary)

                    Button {
                        preset.isFavourite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: preset.isFavourite ? "star.fill" : "star")
                            .foregroundStyle(preset.isFavourite ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(preset.isFavourite ? "Remove from favourites" : "Add to favourites")
                }
            }
            .onDelete { offsets in
                offsets.map { presets[$0] }.forEach(context.delete)
                try? context.save()
            }
            .onMove { from, to in
                var reordered = presets
                reordered.move(fromOffsets: from, toOffset: to)
                for (index, preset) in reordered.enumerated() {
                    preset.sortOrder = index
                }
                try? context.save()
            }
        }
        .navigationTitle("Presets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add preset", systemImage: "plus") { editor = .newPreset }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .overlay {
            if presets.isEmpty {
                ContentUnavailableView("No presets", systemImage: "square.grid.2x2",
                                       description: Text("Add drinks you have often for one-tap logging."))
            }
        }
        .sheet(item: $editor) { mode in
            DrinkEditorView(mode: mode)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
