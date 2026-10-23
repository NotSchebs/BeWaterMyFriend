import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.healthSyncEnabled) private var healthEnabled = false
    @AppStorage(SettingsKey.healthWriteDelay) private var delayRaw = HealthWriteDelay.oneHour.rawValue
    @Environment(\.modelContext) private var context
    private var health = HealthSync.shared

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
                    Toggle("Ninja drop", isOn: $companionEnabled)
                }

                healthSection

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
            .dojoBackground()
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section {
            if health.isAvailable {
                Toggle("Write to Apple Health", isOn: $healthEnabled)
                    .onChange(of: healthEnabled) { _, isOn in
                        guard isOn else { return }
                        Task {
                            try? await health.requestAuthorization()
                            await syncNow(ignoreDelay: false)
                        }
                    }
                if healthEnabled {
                    Picker("When", selection: $delayRaw) {
                        ForEach(HealthWriteDelay.allCases) { delay in
                            Text(delay.label).tag(delay.rawValue)
                        }
                    }
                    Button {
                        Task { await syncNow(ignoreDelay: true) }
                    } label: {
                        HStack {
                            Text("Write pending drinks now")
                            if health.isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(health.isSyncing)
                    Button("Resend all drinks") {
                        Task {
                            await health.resendAll(context: context,
                                                   delay: HealthWriteDelay(rawValue: delayRaw) ?? .oneHour,
                                                   boundary: DayBoundary(dayEndMinutes: dayEndMinutes))
                        }
                    }
                    .disabled(health.isSyncing)
                    if let result = health.lastResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = health.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if let lastSync = health.lastSync {
                        LabeledContent("Last checked", value: lastSync.formatted(date: .omitted, time: .shortened))
                    }
                }
            } else {
                Text("Apple Health isn't available on this device.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Writes water (with each drink's percentage), caffeine, alcohol and known nutrients. Waiting gives you time to fix mistakes before they reach Health; drinks keep their original time. Edits and deletes are updated in Health too. Writing happens while the app is open.")
        }
    }

    private func syncNow(ignoreDelay: Bool) async {
        await health.sync(context: context,
                          delay: HealthWriteDelay(rawValue: delayRaw) ?? .oneHour,
                          boundary: DayBoundary(dayEndMinutes: dayEndMinutes),
                          ignoreDelay: ignoreDelay)
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
        .dojoBackground()
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
