import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes

    var body: some View {
        NavigationStack {
            let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
            let days = Summaries.daily(entries: entries, boundary: boundary)
            let months = Summaries.monthly(days: days, goalML: goalML, calendar: boundary.calendar)

            Group {
                if days.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "calendar",
                                           description: Text("Drinks you log show up here, grouped by day."))
                } else {
                    List {
                        ForEach(months) { month in
                            Section(month.month.formatted(.dateTime.month(.wide).year())) {
                                MonthSummaryRow(month: month)
                                ForEach(days.filter { boundary.calendar.isDate($0.day, equalTo: month.month, toGranularity: .month) }) { day in
                                    NavigationLink(value: day.day) {
                                        DayRow(day: day, goalML: goalML)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .dojoBackground()
            .navigationTitle("History")
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
            }
        }
    }
}

struct MonthSummaryRow: View {
    var month: MonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatTile(title: "Avg / day", value: Format.ml(month.averageGoalFluidPerLoggedDay), symbol: "chart.bar.fill")
                StatTile(title: "Goal reached", value: "\(month.daysGoalReached) / \(month.loggedDays)", symbol: "checkmark.seal.fill")
                StatTile(title: "Caffeine", value: Format.mg(month.caffeineMg), symbol: "bolt.fill")
            }
            Text("Average over the \(Format.count(month.loggedDays, "day", "days")) with entries. Days without entries count as no data, not zero.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct DayRow: View {
    var day: DaySummary
    var goalML: Double

    var body: some View {
        HStack(spacing: 12) {
            ProgressRing(progress: day.progress(goalML: goalML), lineWidth: 5)
                .frame(width: 30, height: 30)
                .overlay {
                    if day.goalReached(goalML: goalML) {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.day.formatted(.dateTime.weekday(.wide).day().month()))
                Text(Format.count(day.entryCount, "drink", "drinks") + (day.caffeineMg > 0 ? " · \(Format.mg(day.caffeineMg)) caffeine" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.ml(day.goalFluidML))
                .font(.subheadline.monospacedDigit())
        }
    }
}

struct DayDetailView: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @State private var editor: EditorMode?

    var body: some View {
        let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
        let interval = boundary.interval(forLogicalDay: day)
        let dayEntries = entries.filter { interval.start <= $0.timestamp && $0.timestamp < interval.end }
        let summary = Summaries.summary(forLogicalDay: day, entries: dayEntries, boundary: boundary)

        List {
            Section("Totals") {
                LabeledContent("Toward goal", value: "\(Format.ml(summary.goalFluidML)) (\(Format.percent(summary.progress(goalML: goalML))))")
                LabeledContent("All fluids", value: Format.ml(summary.totalFluidML))
                LabeledContent("Caffeine", value: Format.mg(summary.caffeineMg))
                LabeledContent("Alcohol", value: "\(Format.amount(summary.alcoholGrams, unit: "g")) · \(Format.standardDrinks(summary.standardDrinks)) std drinks")
            }

            Section("Drinks") {
                ForEach(dayEntries) { entry in
                    Button {
                        editor = .editEntry(entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    EntryActions.delete(offsets.map { dayEntries[$0] }, in: context)
                }
            }

            let known = Nutrient.allCases.filter { $0 != .caffeine && summary.nutrientTotals[$0] != nil }
            if !known.isEmpty {
                Section {
                    ForEach(known) { nutrient in
                        LabeledContent(nutrient.displayName,
                                       value: Format.amount(summary.nutrientTotals[nutrient] ?? 0, unit: nutrient.unit))
                    }
                } header: {
                    Text("Nutrients")
                } footer: {
                    Text("Only from drinks with nutrient data. Drinks without data are not counted as zero.")
                }
            }
        }
        .dojoBackground()
        .navigationTitle(day.formatted(.dateTime.weekday(.abbreviated).day().month()))
        .sheet(item: $editor) { mode in
            DrinkEditorView(mode: mode)
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewData.container)
}
