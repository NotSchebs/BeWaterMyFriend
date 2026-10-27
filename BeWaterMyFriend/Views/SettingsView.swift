import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.healthSyncEnabled) private var healthEnabled = false
    @AppStorage(SettingsKey.healthWriteDelay) private var delayRaw = HealthWriteDelay.oneHour.rawValue
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(SettingsKey.reminderStartMinutes) private var reminderStart = ReminderSettings().startMinutes
    @AppStorage(SettingsKey.reminderEndMinutes) private var reminderEnd = ReminderSettings().endMinutes
    @AppStorage(SettingsKey.reminderIntervalMinutes) private var reminderInterval = ReminderSettings().intervalMinutes
    @AppStorage(SettingsKey.reminderSkipOnTrack) private var reminderSkipOnTrack = ReminderSettings().skipWhenOnTrack
    @AppStorage(SettingsKey.reminderSmart) private var reminderSmart = ReminderSettings().smart
    @State private var notificationsDenied = false
    @Environment(\.modelContext) private var context
    @Query(HealthSync.candidates(now: .now)) private var allEntries: [DrinkEntry]
    private var health = HealthSync.shared
    @State private var isWritingNow = false
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            Form {
                GoalSection()

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
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Ninja drop", isOn: $companionEnabled)
                }

                remindersSection

                healthSection

                Section {
                    NavigationLink("Drink presets") {
                        PresetListView()
                    }
                }

                BackupSection()

                Section("About") {
                    NavigationLink("FAQ") { FAQView() }
                    Text("BeWaterMyFriend tracks water, caffeine, alcohol and nutrients. All values are estimates, not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                DojoTestSection()
                #endif
            }
            .dojoBackground()
            .sensoryFeedback(.success, trigger: health.manualSyncCount)
            .navigationTitle("Settings")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Remind me to drink", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, isOn in
                    Task {
                        if isOn {
                            let allowed = await ReminderScheduler.shared.requestPermission()
                            notificationsDenied = !allowed
                            if !allowed { remindersEnabled = false }
                        }
                        await ReminderScheduler.shared.reschedule(context: context)
                    }
                }
            if notificationsDenied {
                Text("Notifications are turned off for BeWaterMyFriend. You can allow them in the iPhone's Settings app.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if remindersEnabled {
                DatePicker("From", selection: timeBinding($reminderStart), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding($reminderEnd), displayedComponents: .hourAndMinute)
                Picker(reminderSmart ? "About every" : "Every", selection: $reminderInterval) {
                    ForEach([30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) min"
                             : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"))
                            .tag(minutes)
                    }
                }
                Toggle("Smart reminders", isOn: $reminderSmart)
                if reminderSmart {
                    Toggle("Skip when I'm on track", isOn: $reminderSkipOnTrack)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(reminderSmart
                 ? "Smart: a reminder at a random moment within each interval, so it doesn't feel robotic. \"Skip when I'm on track\" leaves out reminders while you're ahead of an even pace. Long-press a reminder to log your last drink again, add a new one, or scan."
                 : "Reminders come exactly every interval, starting at the \"From\" time. Long-press a reminder to log your last drink again, add a new one, or scan.")
        }
        .onChange(of: [reminderStart, reminderEnd, reminderInterval]) {
            Task { await ReminderScheduler.shared.reschedule(context: context) }
        }
        .onChange(of: [reminderSkipOnTrack, reminderSmart]) {
            Task { await ReminderScheduler.shared.reschedule(context: context) }
        }
    }

    /// Edits a "minutes after midnight" value with a time picker.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
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
                    // Status with a refresh button: writes waiting drinks right away.
                    HStack {
                        pendingStatus
                        Spacer()
                        Button {
                            writeNow()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.body.weight(.semibold))
                                .rotationEffect(.degrees(isWritingNow ? 360 : 0))
                                .animation(isWritingNow ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                           value: isWritingNow)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isWritingNow)
                        .accessibilityLabel("Write waiting drinks to Apple Health now")
                    }
                    if showResult, let result = health.lastResult {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .move(edge: .top)))
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

    /// How many drinks are still waiting, and when the next one is due.
    @ViewBuilder
    private var pendingStatus: some View {
        let delay = HealthWriteDelay(rawValue: delayRaw) ?? .oneHour
        let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
        let pending = allEntries.filter(\.needsHealthWrite)
        if pending.isEmpty {
            Label("All drinks are in Apple Health", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            let next = pending
                .map { HealthPlan.dueDate(timestamp: $0.timestamp, modifiedAt: $0.modifiedAt, delay: delay, boundary: boundary) }
                .min() ?? .now
            let when = next <= .now ? "next check" : "next at \(next.formatted(date: .omitted, time: .shortened))"
            Label("\(Format.count(pending.count, "drink", "drinks")) waiting · \(when)", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    /// Writes everything pending, with visible progress and a result that
    /// stays for a few seconds, so the tap always gets feedback.
    private func writeNow() {
        isWritingNow = true
        showResult = false
        Task {
            let started = Date.now
            await syncNow(ignoreDelay: true)
            // If an automatic sync was already running, our tap was queued: wait for it.
            while health.isSyncing { try? await Task.sleep(for: .milliseconds(100)) }
            // Keep the spinner visible briefly, even when writing is instant.
            let elapsed = Date.now.timeIntervalSince(started)
            if elapsed < 0.8 { try? await Task.sleep(for: .seconds(0.8 - elapsed)) }
            withAnimation {
                isWritingNow = false
                showResult = true
            }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { showResult = false }
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
            Section {
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
                        preset.isInQuickLog.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: preset.isInQuickLog ? "square.grid.2x2.fill" : "square.grid.2x2")
                            .foregroundStyle(preset.isInQuickLog ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!preset.isInQuickLog && QuickLogRules.isFull(presets))
                    .accessibilityLabel(preset.isInQuickLog ? "Remove from Quick log" : "Add to Quick log")

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
            } header: {
                Text("Quick log: \(presets.filter(\.isInQuickLog).count) of \(QuickLogRules.maxItems)")
            } footer: {
                Text("▦ shows a drink in the Quick log (at most \(QuickLogRules.maxItems)); ★ puts it first. Drinks not in the Quick log are still found with search when you tap +.")
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
