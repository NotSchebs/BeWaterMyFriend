import SwiftData
import SwiftUI

struct HistoryView: View {
    @State private var openedDay: Date?
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @State private var month = CalendarGrid.startOfMonth(.now, calendar: .current)

    var body: some View {
        NavigationStack {
            let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
            // Only the shown month is calculated (performance): filtering by time is
            // cheap, adding up drinks is not.
            let monthEntries = entries.filter { monthRange(boundary).contains($0.timestamp) }
            let days = Summaries.daily(entries: monthEntries, boundary: boundary)
            let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
            let monthSummary = Summaries.monthly(days: days, goalML: goalML, calendar: boundary.calendar)
                .first { boundary.calendar.isDate($0.month, equalTo: month, toGranularity: .month) }
            let monthDays = days.filter { boundary.calendar.isDate($0.day, equalTo: month, toGranularity: .month) }

            List {
                Section {
                    CalendarMonthView(month: $month, onOpen: { openedDay = $0 }, summaries: byDay, goalML: goalML,
                                      today: boundary.logicalDay(for: .now), calendar: boundary.calendar)
                }
                if let monthSummary {
                    Section("This month") {
                        MonthSummaryRow(month: monthSummary)
                    }
                }
                Section("Days") {
                    if monthDays.isEmpty {
                        Text("No drinks logged in \(month.formatted(.dateTime.month(.wide))).")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(monthDays) { day in
                        NavigationLink(value: day.day) {
                            DayRow(day: day, goalML: goalML)
                        }
                    }
                }
            }
            .dojoBackground()
            .navigationTitle("History")
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
            }
            .navigationDestination(item: $openedDay) { day in
                DayDetailView(day: day)
            }
        }
    }
}

extension HistoryView {
    /// From the start of the month's first logical day to the end of its last.
    fileprivate func monthRange(_ boundary: DayBoundary) -> Range<Date> {
        let calendar = boundary.calendar
        let first = CalendarGrid.startOfMonth(month, calendar: calendar)
        let next = calendar.date(byAdding: .month, value: 1, to: first)!
        let last = calendar.date(byAdding: .day, value: -1, to: next)!
        return boundary.interval(forLogicalDay: first).start..<boundary.interval(forLogicalDay: last).end
    }
}

/// A month calendar: each day shows a small ring of its progress and a seal
/// when the goal was reached. Tapping a day opens it.
struct CalendarMonthView: View {
    @Binding var month: Date
    var onOpen: (Date) -> Void = { _ in }
    var summaries: [Date: DaySummary]
    var goalML: Double
    var today: Date
    var calendar: Calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(month, equalTo: today, toGranularity: .month))
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(CalendarGrid.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(CalendarGrid.cells(forMonthContaining: month, calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { shift(1) } else if value.translation.width > 40 { shift(-1) }
        })
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let summary = summaries[day]
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isFuture = day > today
        let label = VStack(spacing: 2) {
            ZStack {
                if let summary {
                    ProgressRing(progress: summary.progress(goalML: goalML), lineWidth: 3)
                    if summary.goalReached(goalML: goalML) {
                        Circle().fill(Color.accentColor.opacity(0.15))
                    }
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isFuture ? Color.secondary.opacity(0.5) : (isToday ? Color.accentColor : Color.primary))
            }
            .frame(width: 32, height: 32)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 8))
                .foregroundStyle(Dojo.seal)
                .opacity(summary?.goalReached(goalML: goalML) == true ? 1 : 0)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)

        if summary != nil {
            // A plain button, not a NavigationLink: in a List, links add a chevron per cell.
            Button { onOpen(day) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.formatted(date: .long, time: .omitted)), \(Format.percent(summary!.progress(goalML: goalML)))")
        } else {
            label
                .accessibilityLabel("\(day.formatted(date: .long, time: .omitted)), no drinks")
        }
    }

    private func shift(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        if next > today && !calendar.isDate(next, equalTo: today, toGranularity: .month) { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = CalendarGrid.startOfMonth(next, calendar: calendar) }
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
    /// Only this day's drinks (performance), with a day of margin for a custom day end.
    @Query private var entries: [DrinkEntry]

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let from = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        let to = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start
        _entries = Query(filter: #Predicate<DrinkEntry> { $0.timestamp >= from && $0.timestamp < to },
                         sort: \DrinkEntry.timestamp, order: .reverse)
    }
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0
    @State private var editor: EditorMode?

    var body: some View {
        let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
        let interval = boundary.interval(forLogicalDay: day)
        let dayEntries = entries.filter { interval.start <= $0.timestamp && $0.timestamp < interval.end }
        let summary = Summaries.summary(forLogicalDay: day, entries: dayEntries, boundary: boundary)

        List {
            if companionEnabled && !dayEntries.isEmpty {
                Section {
                    // Static (no animation): just how the day looked.
                    HStack(spacing: 16) {
                        NinjaDrop(progress: summary.progress(goalML: goalML), belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)),
                                  layers: CompanionLogic.fillLayers(entries: dayEntries, goalML: goalML),
                                  mood: CompanionLogic.dayMood(summary), animated: false)
                            .frame(width: 48, height: 63)
                            .padding(.trailing, 14)
                        Text(CompanionLogic.dayCaption(summary, goalML: goalML))
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }

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
