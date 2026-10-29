import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    /// Only recent drinks (performance): older days live in the stored `DojoArchive`.
    @Query private var entries: [DrinkEntry]
    @Query(sort: [SortDescriptor(\DrinkPreset.sortOrder), SortDescriptor(\DrinkPreset.name)])
    private var presets: [DrinkPreset]
    @AppStorage(SettingsKey.dojoArchive) private var archiveData = Data()

    init() {
        // A bit more than the live days, so a gap before the archive catches up is covered.
        let cutoff = Calendar.current.date(byAdding: .day, value: -(DojoArchive.liveDays + 3), to: .now) ?? .now
        _entries = Query(filter: #Predicate<DrinkEntry> { $0.timestamp >= cutoff },
                         sort: \DrinkEntry.timestamp, order: .reverse)
    }

    private var archive: DojoArchive {
        (try? JSONDecoder().decode(DojoArchive.self, from: archiveData)) ?? DojoArchive()
    }

    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled

    /// Highest goal-day count ever reached; belts are based on it so they're never lost.
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.dojoBelt) private var awardedBeltRaw = 0
    @AppStorage(SettingsKey.prestigeLevel) private var prestigeLevel = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0

    @State private var editor: EditorMode?
    @State private var showScanner = false
    @State private var showAddDrink = false
    @State private var showAlcoholInfo = false
    @State private var flashedPreset: PersistentIdentifier?
    private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var loggedCount = 0
    @State private var showDojo = false
    @State private var earnedBelt: Belt?
    @State private var splashTrigger = 0
    /// The drop gulps once for every new drink today.
    @State private var reactionCount = 0

    var body: some View {
        NavigationStack {
            // Re-evaluate every minute so "today" rolls over at the day end.
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add drink", systemImage: "plus") { showAddDrink = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan", systemImage: "barcode.viewfinder") { showScanner = true }
                }
            }
            .sheet(item: $editor) { mode in
                DrinkEditorView(mode: mode)
            }
            .sheet(isPresented: $showAddDrink) {
                AddDrinkView(
                    onPick: { draft in present { editor = .prefilled(draft) } },
                    onNew: { present { editor = .newEntry } },
                    onScan: { present { showScanner = true } }
                )
            }
            .sheet(isPresented: $showScanner) {
                ScanView { draft in
                    // Open the review once the scanner sheet has gone.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        editor = .scanned(draft)
                    }
                }
            }
            .fullScreenCover(item: $earnedBelt) { belt in
                BeltEarnedView(belt: belt)
            }
            .sensoryFeedback(.success, trigger: loggedCount)
            // Opened from a reminder's "New drink" or "Scan" button (or a link).
            .onChange(of: router.pendingAction, initial: true) { handlePendingAction() }
            .onChange(of: scenePhase) { handlePendingAction() }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
        let today = boundary.logicalDay(for: now)
        let interval = boundary.interval(forLogicalDay: today)
        let todaysEntries = entries.filter { interval.contains($0.timestamp) && $0.timestamp < interval.end }
        let summary = Summaries.summary(forLogicalDay: today, entries: todaysEntries, boundary: boundary)
        let progress = summary.progress(goalML: goalML)
        let stats = DojoProgress.stats(recentDays: Summaries.daily(entries: entries, boundary: boundary),
                                       archive: archive, goalML: goalML, today: today, calendar: boundary.calendar)
        let goalDays = DojoProgress.rankGoalDays(bestTotal: bestGoalDays, currentTotal: stats.goalDays,
                                                 prestigeBase: prestigeBase)
        let belt = Belt.belt(forGoalDays: goalDays)
        let layers = CompanionLogic.fillLayers(entries: todaysEntries, goalML: goalML)
        let legend = CompanionLogic.tintTotals(entries: todaysEntries)
        // The timeline's date is the start of the minute; a drink logged a few
        // seconds later must already count, so use the exact time here.
        let moodState = CompanionLogic.moodState(entries: entries, now: max(now, .now))
        let mood = moodState.mood

        ScrollViewReader { scroller in
        List {
            Section {
                progressHeader(summary: summary, progress: progress, layers: layers, legend: legend) {
                    withAnimation { scroller.scrollTo(Self.drinksAnchor, anchor: .top) }
                }
                .overlay { SplashBurst(trigger: splashTrigger) }
                if companionEnabled {
                    CompanionView(progress: progress, layers: layers, mood: mood,
                                  reason: moodState.reason, until: moodState.until, reaction: reactionCount, belt: belt,
                                  prestige: prestigeLevel, stats: stats,
                                  goalDaysTowardBelt: goalDays) { showDojo = true }
                }
            }
            .listRowBackground(
                ZStack {
                    Dojo.card
                    SeigaihaPattern().opacity(0.05)
                }
            )

            Section {
                QuickLogGrid(presets: sortedPresets, flashed: flashedPreset) { preset in
                    log(preset)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text("Quick log")
            } footer: {
                Text("Tap a drink to log it now. Manage presets in Settings.")
            }

            Section("Today's drinks") {
                if todaysEntries.isEmpty {
                    Text("Nothing logged yet.")
                        .foregroundStyle(.secondary)
                        .id(Self.drinksAnchor)
                } else {
                    ForEach(todaysEntries) { entry in
                        Button {
                            editor = .editEntry(entry)
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .tint(.primary)
                        .id(entry.id == todaysEntries.first?.id ? AnyHashable(Self.drinksAnchor) : AnyHashable(entry.id))
                    }
                    .onDelete { offsets in
                        EntryActions.delete(offsets.map { todaysEntries[$0] }, in: context)
                    }
                }
            }
        }
        }
        .dojoBackground()
        .sheet(isPresented: $showDojo) {
            DojoView(progress: progress, layers: layers, mood: mood, belt: belt, stats: stats,
                     goalDays: goalDays, prestige: prestigeLevel) {
                startPrestige(totalGoalDays: max(bestGoalDays, stats.goalDays))
            }
        }
        .onChange(of: stats.goalDays, initial: true) { _, newValue in
            updateRank(goalDays: newValue)
        }
        // Once a day (and on first launch), move finished days into the archive.
        .task(id: today) { advanceArchive(today: today, boundary: boundary) }
        .onChange(of: todaysEntries.count) { old, new in
            if new > old { reactionCount += 1 }
        }
        .onChange(of: progress >= 1) { wasReached, isReached in
            if isReached && !wasReached { splashTrigger += 1 }
        }
    }

    /// Counts finished days older than a week into the stored archive. On first
    /// launch this reads the whole history once; afterwards only a day or two.
    private func advanceArchive(today: Date, boundary: DayBoundary) {
        let current = archive
        let limit = DojoArchive.archiveLimit(today: today, calendar: boundary.calendar)
        guard current.throughDay.map({ $0 < limit }) ?? true else { return }
        let from = current.throughDay.map { boundary.interval(forLogicalDay: $0).end } ?? .distantPast
        let to = boundary.interval(forLogicalDay: limit).end
        let descriptor = FetchDescriptor<DrinkEntry>(predicate: #Predicate { $0.timestamp >= from && $0.timestamp < to })
        let old = (try? context.fetch(descriptor)) ?? []
        let next = current.advanced(through: limit, days: Summaries.daily(entries: old, boundary: boundary),
                                    goalML: goalML, calendar: boundary.calendar)
        archiveData = (try? JSONEncoder().encode(next)) ?? Data()
    }

    /// Remembers the best goal-day count and celebrates a newly earned belt.
    private func updateRank(goalDays totalGoalDays: Int) {
        bestGoalDays = max(bestGoalDays, totalGoalDays)
        let belt = Belt.belt(forGoalDays: DojoProgress.rankGoalDays(bestTotal: bestGoalDays,
                                                                    currentTotal: totalGoalDays,
                                                                    prestigeBase: prestigeBase))
        if belt.rawValue > awardedBeltRaw {
            awardedBeltRaw = belt.rawValue
            if companionEnabled { earnedBelt = belt }
        }
    }

    /// Prestige (only after the user confirmed in the dojo): ranks start again
    /// at white belt, the prestige level goes up. History and goal days stay.
    private func startPrestige(totalGoalDays: Int) {
        prestigeBase = totalGoalDays
        prestigeLevel += 1
        awardedBeltRaw = Belt.white.rawValue
    }

    /// "Goal includes +1,000 ml for workouts · +500 ml for heat", when there are extras.
    private var goalExtrasText: String? {
        guard let b = GoalService.shared.breakdown else { return nil }
        var parts: [String] = []
        if b.workoutML > 0 { parts.append("+\(Format.ml(b.workoutML)) for workouts") }
        if b.heatML > 0 { parts.append("+\(Format.ml(b.heatML)) for heat") }
        if b.coldML > 0 { parts.append("+\(Format.ml(b.coldML)) for cold") }
        return parts.isEmpty ? nil : "Goal includes " + parts.joined(separator: " · ")
    }

    /// iOS drops sheets that are presented while the app is still coming to
    /// the foreground. So: wait until the app is active, close whatever sheet
    /// is open, then show the requested screen.
    private func handlePendingAction() {
        guard let action = router.pendingAction, scenePhase == .active else { return }
        router.pendingAction = nil
        let wasShowingSheet = editor != nil || showScanner || showAddDrink || showDojo
        editor = nil
        showScanner = false
        showAddDrink = false
        showDojo = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(wasShowingSheet ? 600 : 300))
            switch action {
            case .newDrink: editor = .newEntry
            case .scan: showScanner = true
            }
        }
    }

    /// Opens the next sheet once the current one has gone (iOS ignores a
    /// presentation while another sheet is still closing).
    private func present(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }

    /// Scroll target for tapping the ring.
    private static let drinksAnchor = "todaysDrinks"

    private func progressHeader(summary: DaySummary, progress: Double, layers: [FillLayer],
                                legend: [TintTotal], onRingTap: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            // Tapping the ring jumps to today's drinks.
            Button(action: onRingTap) {
                ZStack {
                    ProgressRing(progress: progress, layers: layers)
                        .frame(width: 170, height: 170)
                    VStack(spacing: 2) {
                        Text(Format.ml(summary.goalFluidML))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .font(.title2.bold())
                            .contentTransition(.numericText())
                        Text("of \(Format.ml(goalML))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Format.percent(progress))
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 130)
                    // The ring has a fixed size, so its text stops growing at some point.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows today's drinks")

            if !legend.isEmpty {
                ColorLegend(totals: legend)
            }

            if GoalService.isSuggested(), let extras = goalExtrasText {
                Label(extras, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            StatTileRow {
                StatTile(title: "Caffeine", value: Format.mg(summary.caffeineMg), symbol: "bolt.fill")
                Button { showAlcoholInfo = true } label: {
                    StatTile(title: "Std. drinks ⓘ", value: Format.standardDrinks(summary.standardDrinks),
                             symbol: "wineglass.fill")
                }
                .buttonStyle(.plain)
                .alert("Standard drinks", isPresented: $showAlcoholInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(FAQ.standardDrink)
                }
                StatTile(title: "All fluids", value: Format.ml(summary.totalFluidML), symbol: "drop")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Favourites first, then the rest in the user's order.
    private var sortedPresets: [DrinkPreset] {
        QuickLogRules.visible(presets)
    }

    private func log(_ preset: DrinkPreset) {
        let entry = preset.makeEntry()
        context.insert(entry)
        try? context.save()
        loggedCount += 1
        // Tile checkmark for a moment; "Logged … · Undo" at the bottom of the screen.
        flashedPreset = preset.persistentModelID
        withAnimation(.spring(duration: 0.35)) { router.showLogged(entry) }
        let id = preset.persistentModelID
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if flashedPreset == id { withAnimation { flashedPreset = nil } }
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
