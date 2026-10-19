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

    @State private var editor: EditorMode?
    @State private var loggedCount = 0

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
            }
            .sheet(item: $editor) { mode in
                DrinkEditorView(mode: mode)
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

        List {
            Section {
                progressHeader(summary: summary, progress: progress)
                if companionEnabled {
                    CompanionView(progress: progress)
                }
            }

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
                } else {
                    ForEach(todaysEntries) { entry in
                        Button {
                            editor = .editEntry(entry)
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { todaysEntries[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                }
            }
        }
    }

    private func progressHeader(summary: DaySummary, progress: Double) -> some View {
        VStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: progress)
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
            .accessibilityElement(children: .combine)

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
                                .foregroundStyle(preset.category.countsTowardGoal ? Color.accentColor : .orange)
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
                .foregroundStyle(entry.category.countsTowardGoal ? Color.accentColor : .orange)
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
