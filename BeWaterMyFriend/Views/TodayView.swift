import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]
    @Query(sort: [SortDescriptor(\DrinkPreset.sortOrder), SortDescriptor(\DrinkPreset.name)])
    private var presets: [DrinkPreset]

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
    @State private var loggedCount = 0
    @State private var showDojo = false
    @State private var earnedBelt: Belt?
    @State private var splashTrigger = 0

    var body: some View {
        NavigationStack {
            // Re-evaluate every minute so "today" rolls over at the day end.
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add drink", systemImage: "plus") { editor = .newEntry }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan", systemImage: "barcode.viewfinder") { showScanner = true }
                }
            }
            .sheet(item: $editor) { mode in
                DrinkEditorView(mode: mode)
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
        let stats = DojoProgress.stats(days: Summaries.daily(entries: entries, boundary: boundary),
                                       goalML: goalML, today: today, calendar: boundary.calendar)
        let goalDays = DojoProgress.rankGoalDays(bestTotal: bestGoalDays, currentTotal: stats.goalDays,
                                                 prestigeBase: prestigeBase)
        let belt = Belt.belt(forGoalDays: goalDays)
        let layers = CompanionLogic.fillLayers(entries: todaysEntries, goalML: goalML)
        let legend = CompanionLogic.tintTotals(entries: todaysEntries)
        // The timeline's date is the start of the minute; a drink logged a few
        // seconds later must already count, so use the exact time here.
        let mood = CompanionLogic.mood(entries: entries, now: max(now, .now))

        ScrollViewReader { scroller in
        List {
            Section {
                progressHeader(summary: summary, progress: progress, layers: layers, legend: legend) {
                    withAnimation { scroller.scrollTo(Self.drinksAnchor, anchor: .top) }
                }
                .overlay { SplashBurst(trigger: splashTrigger) }
                if companionEnabled {
                    CompanionView(progress: progress, layers: layers, mood: mood, belt: belt,
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
                QuickLogGrid(presets: sortedPresets) { preset in
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
        .onChange(of: progress >= 1) { wasReached, isReached in
            if isReached && !wasReached { splashTrigger += 1 }
        }
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
                            .font(.title2.bold())
                            .contentTransition(.numericText())
                        Text("of \(Format.ml(goalML))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Format.percent(progress))
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows today's drinks")

            if !legend.isEmpty {
                ColorLegend(totals: legend)
            }

            HStack {
                StatTile(title: "Caffeine", value: Format.mg(summary.caffeineMg), symbol: "bolt.fill")
                StatTile(title: "Alcohol", value: "\(Format.standardDrinks(summary.standardDrinks)) std",
                         symbol: "wineglass.fill")
                StatTile(title: "All fluids", value: Format.ml(summary.totalFluidML), symbol: "drop")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Favourites first, then the rest in the user's order.
    private var sortedPresets: [DrinkPreset] {
        presets.filter(\.isFavourite) + presets.filter { !$0.isFavourite }
    }

    private func log(_ preset: DrinkPreset) {
        context.insert(preset.makeEntry())
        try? context.save()
        loggedCount += 1
    }
}

/// What each colour in the ring and the drop means, with today's amount.
struct ColorLegend: View {
    var totals: [TintTotal]

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(totals, id: \.tint) { total in
                HStack(spacing: 6) {
                    Circle()
                        .fill(total.tint.ringColor)
                        .frame(width: 10, height: 10)
                    Text(total.tint.displayName)
                        .font(.caption)
                        .lineLimit(1)
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

struct StatTile: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
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
                        .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 14))
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

#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
