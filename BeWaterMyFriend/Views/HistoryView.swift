import SwiftData
import SwiftUI

struct HistoryView: View {
    @State private var openedDay: Date?
    @Query(sort: \DrinkEntry.timestamp, order: .reverse) private var entries: [DrinkEntry]
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @State private var month = CalendarGrid.startOfMonth(.now, calendar: .current)
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0

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
                                      today: boundary.logicalDay(for: .now), calendar: boundary.calendar,
                                      belt: companionEnabled ? Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)) : nil)
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
                        .accessibilityIdentifier("dayRow")
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
    /// The drop's belt; nil when the companion is off.
    var belt: Belt? = nil

    /// The drop stands on the month's best day and hops to the new one when the
    /// month changes; tapped, it says what made the day the best.
    @Namespace private var dropSpace
    @State private var showBestLine = false
    @State private var taps = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let best = belt == nil ? nil : CompanionLogic.bestDay(in: summaries.values.filter {
            calendar.isDate($0.day, equalTo: month, toGranularity: .month)
        })
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
                        dayCell(day, best: best)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // Seven fixed-width columns: day numbers stop growing before they overflow the rings.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { shift(1) } else if value.translation.width > 40 { shift(-1) }
        })
    }

    @ViewBuilder
    private func dayCell(_ day: Date, best: DaySummary?) -> some View {
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

        Group {
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
        // Outside the day's button, so tapping the day still opens it.
        .overlay(alignment: .top) {
            if let belt, let best, calendar.isDate(best.day, inSameDayAs: day) {
                bestDayDrop(best, belt: belt)
            }
        }
    }

    private func bestDayDrop(_ best: DaySummary, belt: Belt) -> some View {
        let line = CompanionLines.bestDay(ml: best.goalFluidML,
                                          dayText: best.day.formatted(.dateTime.weekday(.abbreviated).day()),
                                          monthText: month.formatted(.dateTime.month(.wide)), seed: taps)
        return Button {
            showBestLine = true
        } label: {
            // Static: one tiny drop with that day's face, no animation cost.
            NinjaDrop(progress: best.progress(goalML: goalML), belt: belt, mood: CompanionLogic.dayMood(best), animated: false)
                .frame(width: 15, height: 20)
                .padding(4)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: "bestDayDrop", in: dropSpace)
        // On the ring's top-right edge.
        .offset(x: 18, y: -10)
        .popover(isPresented: $showBestLine) {
            Text(line)
                .font(.footnote)
                .padding(12)
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showBestLine) { if !showBestLine { taps += 1 } }
        .accessibilityLabel(line)
    }

    private func shift(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        if next > today && !calendar.isDate(next, equalTo: today, toGranularity: .month) { return }
        // A springy change, so the drop visibly hops to the new month's best day.
        withAnimation(.spring(duration: 0.45, bounce: 0.35)) { month = CalendarGrid.startOfMonth(next, calendar: calendar) }
    }
}

struct MonthSummaryRow: View {
    var month: MonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatTileRow {
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
                    DayReplayView(entries: dayEntries, goalML: goalML,
                                  belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)),
                                  finalMood: CompanionLogic.dayMood(summary),
                                  caption: CompanionLogic.dayCaption(summary, goalML: goalML,
                                                                     seed: CompanionLines.daySeed(day, calendar: boundary.calendar)))
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

/// The day view's drop. Still, it shows how the day ended. Tapped, it replays
/// the day drink by drink (fill, colours, moods), using the same rules as the
/// Today screen. It only animates during the replay.
struct DayReplayView: View {
    var entries: [DrinkEntry]
    var goalML: Double
    var belt: Belt
    var finalMood: CompanionMood
    var caption: String

    @State private var step: Int?
    @State private var reaction = 0
    @State private var player: Task<Void, Never>?
    @State private var replays = 0

    private var steps: [CompanionLogic.ReplayStep] { CompanionLogic.replay(entries: entries, goalML: goalML) }

    var body: some View {
        let steps = steps
        let current = step.flatMap { $0 >= 0 && $0 < steps.count ? steps[$0] : nil }
        let playing = step != nil

        HStack(alignment: .center, spacing: 10) {
            Button(action: { play(steps) }) {
                NinjaDrop(progress: playing ? (current?.progress ?? 0) : (steps.last?.progress ?? 0),
                          belt: belt,
                          layers: playing ? (current?.layers ?? []) : CompanionLogic.fillLayers(entries: entries, goalML: goalML),
                          mood: playing ? (current?.mood ?? .calm) : finalMood,
                          reaction: reaction, animated: playing)
                    .frame(width: 52, height: 68)
                    .padding(.leading, 4)
                    .padding(.trailing, 16)
                    .overlay(alignment: .bottomLeading) {
                        if !playing {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Dojo.ink, Dojo.card)
                                .offset(x: -6, y: 4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Replaying the day" : "Replay the day")
            .accessibilityIdentifier("replayButton")

            // No text animation: steps can be 0.35 s apart and a cross-fade gets messy.
            SpeechBubble(text: bubbleText(current))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .onDisappear { player?.cancel() }
    }

    private func bubbleText(_ current: CompanionLogic.ReplayStep?) -> String {
        guard step != nil else { return caption }
        guard let current else { return CompanionLines.replayStart(seed: replays) }
        return "\(current.time.formatted(date: .omitted, time: .shortened)) · "
            + CompanionLines.replayLine(name: current.name, mood: current.mood, moodChanged: current.moodChanged)
    }

    /// About 3 seconds in total, whatever the number of drinks (0.35–0.9 s per drink).
    private func play(_ steps: [CompanionLogic.ReplayStep]) {
        player?.cancel()
        replays += 1
        let pause = min(max(3.0 / Double(max(steps.count, 1)), 0.35), 0.9)
        player = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.25)) { step = -1 }
            try? await Task.sleep(for: .milliseconds(700))
            for i in steps.indices {
                guard !Task.isCancelled else { return }
                step = i
                reaction += 1
                try? await Task.sleep(for: .seconds(pause))
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { step = nil }
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewData.container)
}
