import Charts
import SwiftData
import SwiftUI

/// Trends over the last week or month: daily amounts against the goal,
/// weekly averages, weekdays, drink types, caffeine and alcohol.
struct StatsView: View {
    /// The last 10 weeks cover every chart (30 days + the 30 before for the
    /// trend, 8 weeks of averages); older drinks aren't loaded (performance).
    @Query private var entries: [DrinkEntry]

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -70, to: .now) ?? .now
        _entries = Query(filter: #Predicate<DrinkEntry> { $0.timestamp >= cutoff }, sort: \DrinkEntry.timestamp)
    }
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.dayEndMinutes) private var dayEndMinutes = SettingsDefault.dayEndMinutes
    @State private var period = Period.week
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0

    /// Where the drop stands: a bar the user tapped, or else the spot the
    /// insight sentence is about. There's only ever one drop on the screen.
    @State private var pin: Pin?
    /// Counts taps: picks the wording and plays the landing "gulp".
    @State private var taps = 0
    /// The donut slice the drop sits in; nil = no drop there until you tap.
    @State private var donutTint: DrinkTint?
    /// Separate from `taps`, so the drop on the bar charts doesn't gulp too.
    @State private var donutTaps = 0

    enum ChartKind { case daily, weekday, caffeine, alcohol }

    struct Pin: Equatable {
        var kind: ChartKind
        var day: Date?
        var weekday: Int?
    }

    struct DropSpot {
        var kind: ChartKind
        var day: Date?
        var weekday: Int?
        var text: String
        var mood: CompanionMood
        var progress: Double
    }

    /// Room above a chart for the drop's speech bubble.
    private let bubbleSpace: CGFloat = 64

    enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        NavigationStack {
            let boundary = DayBoundary(dayEndMinutes: dayEndMinutes)
            let today = boundary.logicalDay(for: .now)
            let report = StatsCalculator.report(entries: entries, days: period.days, goalML: goalML,
                                                today: today, boundary: boundary)
            let weekdays = StatsCalculator.weekdays(report.points, calendar: boundary.calendar)
            let spot = dropSpot(report: report, weekdays: weekdays, calendar: boundary.calendar, today: today)
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack {
                        StatTile(title: "Avg / day", value: report.averageML.map(Format.ml) ?? "–", symbol: "drop.fill")
                        StatTile(title: "Goal days", value: "\(report.goalDays)/\(period.days)", symbol: "checkmark.seal.fill")
                        StatTile(title: "Trend", value: trendText(report.averageChangePercent), symbol: trendSymbol(report.averageChangePercent))
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Trend compares the average with the \(period == .week ? "week" : "30 days") before. Days without entries are left out, not counted as zero.")
                }

                Section("Daily amount") {
                    dailyChart(report, spot: spot, calendar: boundary.calendar)
                }

                if period == .month {
                    Section("Weekly average") {
                        weeklyChart(StatsCalculator.weeks(entries: entries, weeks: 8, goalML: goalML, today: today, boundary: boundary))
                    }
                }

                if weekdays.count > 1 {
                    Section("By weekday") {
                        weekdayChart(weekdays, spot: spot, calendar: boundary.calendar)
                    }
                }

                if !report.tintTotals.isEmpty {
                    Section("What you drank") {
                        drinkTypeChart(report.tintTotals)
                    }
                }

                Section("Caffeine") {
                    perDayChart(report.points.map { ($0.day, $0.caffeineMg) }, kind: .caffeine, spot: spot,
                                calendar: boundary.calendar, color: DrinkTint.coffee.color, unit: "mg")
                    LabeledContent("In total", value: Format.mg(report.totalCaffeineMg))
                    LabeledContent("Per day with caffeine",
                                   value: Format.mg(average(report.points.map(\.caffeineMg))))
                }

                Section {
                    perDayChart(report.points.map { ($0.day, $0.standardDrinks) }, kind: .alcohol, spot: spot,
                                calendar: boundary.calendar, color: DrinkTint.beer.color, unit: "std. drinks")
                    LabeledContent("Standard drinks in total", value: Format.standardDrinks(report.totalStandardDrinks))
                    LabeledContent("Days with alcohol",
                                   value: "\(report.points.filter { $0.standardDrinks > 0 }.count) of \(period.days)")
                } header: {
                    Text("Alcohol")
                } footer: {
                    Text("1 standard drink = 10 g of pure alcohol.")
                }

                if let best = report.bestDay, let ml = best.ml {
                    Section {
                        LabeledContent("Best day", value: "\(best.day.formatted(.dateTime.weekday(.abbreviated).day().month())) · \(Format.ml(ml))")
                    }
                }
            }
            .dojoBackground()
            .navigationTitle("Stats")
            .onChange(of: period) {
                pin = nil
                donutTint = nil
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No stats yet", systemImage: "chart.bar",
                                           description: Text("Log drinks for a few days to see your trends."))
                }
            }
        }
    }

    // MARK: Charts

    private func dailyChart(_ report: StatsReport, spot: DropSpot?, calendar: Calendar) -> some View {
        let top = max(report.points.compactMap(\.ml).max() ?? 0, goalML)
        return Chart {
            ForEach(report.points) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("ml", point.ml ?? 0))
                    .foregroundStyle(point.goalReached ? Color.accentColor : Color.accentColor.opacity(0.45))
                    .cornerRadius(4)
            }
            RuleMark(y: .value("Goal", goalML))
                .foregroundStyle(Dojo.seal)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal").font(.caption2).foregroundStyle(Dojo.seal)
                }
        }
        .chartXAxis {
            if period == .week {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) }
            }
        }
        .chartYScale(domain: 0...(companionEnabled ? top * 1.35 : top))
        .chartOverlay { proxy in
            dropLayer(proxy, kind: .daily, spot: spot, calendar: calendar,
                      y: { day in report.points.first { calendar.isDate($0.day, inSameDayAs: day) }?.ml ?? 0 })
        }
        .frame(height: 200)
        .padding(.vertical, 6)
        .padding(.top, spot?.kind == .daily ? bubbleSpace : 0)
        .accessibilityLabel("Daily amounts against your goal")
    }

    private func weeklyChart(_ weeks: [WeekPoint]) -> some View {
        Chart {
            ForEach(weeks) { week in
                if let avg = week.averageML {
                    LineMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("ml", avg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("ml", avg))
                        .foregroundStyle(Color.accentColor)
                        .annotation(position: .top) {
                            Text("\(week.goalDays)✓").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                }
            }
            RuleMark(y: .value("Goal", goalML))
                .foregroundStyle(Dojo.seal.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
        }
        .frame(height: 180)
        .padding(.vertical, 6)
    }

    private func weekdayChart(_ points: [WeekdayPoint], spot: DropSpot?, calendar: Calendar) -> some View {
        let symbols = calendar.shortWeekdaySymbols
        let top = max(points.map(\.averageML).max() ?? 0, 1)
        return Chart(points) { point in
            BarMark(x: .value("Weekday", symbols[point.weekday - 1]), y: .value("ml", point.averageML))
                .foregroundStyle(Dojo.water.gradient)
                .cornerRadius(4)
        }
        .chartYScale(domain: 0...(companionEnabled ? top * 1.4 : top))
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
                Rectangle().fill(.clear).contentShape(.rect)
                    .onTapGesture { location in
                        guard let symbol = proxy.value(atX: location.x - plot.minX, as: String.self),
                              let index = symbols.firstIndex(of: symbol) else { return }
                        tapped(Pin(kind: .weekday, weekday: index + 1))
                    }
                if let spot, spot.kind == .weekday, let weekday = spot.weekday,
                   let point = points.first(where: { $0.weekday == weekday }),
                   let px = proxy.position(forX: symbols[weekday - 1]), let py = proxy.position(forY: point.averageML) {
                    dropAndBubble(spot, x: plot.minX + px, y: plot.minY + py, width: geo.size.width)
                }
            }
        }
        .frame(height: 160)
        .padding(.vertical, 6)
        .padding(.top, spot?.kind == .weekday ? bubbleSpace : 0)
    }

    /// Tapping a slice puts the drop in the middle of the donut, filled with that
    /// drink's colour and its face (coffee → hyper …), with a bubble below.
    /// Tapping the slice again or the middle hides it.
    private func drinkTypeChart(_ totals: [TintTotal]) -> some View {
        let total = totals.reduce(0) { $0 + $1.ml }
        let selected = donutTint.flatMap { tint in totals.first { $0.tint == tint } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Chart(totals, id: \.tint) { slice in
                    SectorMark(angle: .value("ml", slice.ml), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(slice.tint.ringColor)
                        .opacity(selected == nil || selected?.tint == slice.tint ? 1 : 0.35)
                        .cornerRadius(3)
                }
                .chartOverlay { _ in
                    GeometryReader { geo in
                        Color.clear.contentShape(.rect)
                            .onTapGesture { location in tappedDonut(at: location, size: geo.size, totals: totals) }
                    }
                }
                .overlay {
                    if let selected, total > 0 {
                        NinjaDrop(progress: 1, belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)),
                                  layers: [FillLayer(tint: selected.tint, fraction: selected.ml / total)],
                                  mood: CompanionLogic.mood(for: selected.tint), reaction: donutTaps, animated: false)
                            .frame(width: 30, height: 40)
                            .allowsHitTesting(false)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 120, height: 120)
                ColorLegend(totals: totals)
            }
            if let selected, total > 0 {
                SpeechBubble(text: CompanionLines.statsDrinkType(name: selected.tint.displayName, ml: selected.ml,
                                                                 share: selected.ml / total, seed: donutTaps),
                             tailEdge: .top, tailX: 60)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
    }

    /// Which slice was tapped: the angle from 12 o'clock, clockwise (the way
    /// Swift Charts draws the donut), compared with each drink's running total.
    private func tappedDonut(at point: CGPoint, size: CGSize, totals: [TintTotal]) {
        guard companionEnabled else { return }
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let radius = min(size.width, size.height) / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        let total = totals.reduce(0) { $0 + $1.ml }
        var hit: DrinkTint?
        if distance >= radius * 0.55, distance <= radius, total > 0 {
            var angle = atan2(dx, -dy)
            if angle < 0 { angle += 2 * .pi }
            let target = angle / (2 * .pi) * total
            var running = 0.0
            hit = totals.first { slice in
                running += slice.ml
                return target <= running
            }?.tint
        }
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            if let hit, hit != donutTint {
                donutTint = hit
                donutTaps += 1
            } else {
                donutTint = nil
            }
        }
    }

    /// Small bar chart per day (caffeine, alcohol).
    private func perDayChart(_ values: [(Date, Double)], kind: ChartKind, spot: DropSpot?, calendar: Calendar,
                             color: Color, unit: String) -> some View {
        let top = max(values.map(\.1).max() ?? 0, kind == .alcohol ? 1 : 50)
        return Chart(values, id: \.0) { day, value in
            BarMark(x: .value("Day", day, unit: .day), y: .value(unit, value))
                .foregroundStyle(color)
                .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxisLabel(unit)
        .chartYScale(domain: 0...(companionEnabled ? top * 1.6 : top))
        .chartOverlay { proxy in
            dropLayer(proxy, kind: kind, spot: spot, calendar: calendar,
                      y: { day in values.first { calendar.isDate($0.0, inSameDayAs: day) }?.1 ?? 0 })
        }
        .frame(height: 110)
        .padding(.vertical, 6)
        .padding(.top, spot?.kind == kind ? bubbleSpace : 0)
    }

    // MARK: The drop in the charts

    /// Tap catcher plus the drop for charts with one bar per day.
    private func dropLayer(_ proxy: ChartProxy, kind: ChartKind, spot: DropSpot?, calendar: Calendar,
                           y value: @escaping (Date) -> Double) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            Rectangle().fill(.clear).contentShape(.rect)
                .onTapGesture { location in
                    guard let date = proxy.value(atX: location.x - plot.minX, as: Date.self) else { return }
                    tapped(Pin(kind: kind, day: calendar.startOfDay(for: date)))
                }
            if let spot, spot.kind == kind, let day = spot.day,
               // Bars of a day are centred on its middle.
               let px = proxy.position(forX: calendar.date(byAdding: .hour, value: 12, to: day) ?? day),
               let py = proxy.position(forY: value(day)) {
                dropAndBubble(spot, x: plot.minX + px, y: plot.minY + py, width: geo.size.width)
            }
        }
    }

    /// The drop standing on top of a bar, its bubble above the chart pointing at it.
    @ViewBuilder
    private func dropAndBubble(_ spot: DropSpot, x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        SpeechBubble(text: spot.text, tailEdge: .bottom, tailX: x)
            .frame(width: width, alignment: .leading)
            .frame(height: bubbleSpace - 4, alignment: .bottom)
            .offset(y: -bubbleSpace)
            .animation(.snappy(duration: 0.25), value: spot.text)
        NinjaDrop(progress: spot.progress, belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)),
                  mood: spot.mood, reaction: taps, animated: false)
            .frame(width: 26, height: 34)
            .position(x: x, y: y - 18)
            // The hop from bar to bar.
            .animation(.spring(duration: 0.4, bounce: 0.45), value: x)
            .allowsHitTesting(false)
    }

    private func tapped(_ newPin: Pin) {
        guard companionEnabled else { return }
        taps += 1
        pin = newPin
    }

    /// Where the drop stands and what it says: the tapped bar, else the insight.
    private func dropSpot(report: StatsReport, weekdays: [WeekdayPoint], calendar: Calendar, today: Date) -> DropSpot? {
        guard companionEnabled else { return nil }
        if let pin {
            return spot(for: pin, report: report, weekdays: weekdays, calendar: calendar, text: nil)
        }
        guard let insight = StatsInsight.make(report: report, entries: entries, calendar: calendar,
                                              seed: CompanionLines.daySeed(today, calendar: calendar)) else { return nil }
        let target: Pin = switch insight.target {
        case .daily(let day): Pin(kind: .daily, day: day)
        case .weekday(let weekday): Pin(kind: .weekday, weekday: weekday)
        case .caffeine(let day): Pin(kind: .caffeine, day: day)
        }
        return spot(for: target, report: report, weekdays: weekdays, calendar: calendar, text: insight.text)
    }

    private func spot(for pin: Pin, report: StatsReport, weekdays: [WeekdayPoint], calendar: Calendar,
                      text: String?) -> DropSpot? {
        if pin.kind == .weekday {
            guard let weekday = pin.weekday, let point = weekdays.first(where: { $0.weekday == weekday }) else { return nil }
            return DropSpot(kind: .weekday, weekday: weekday,
                            text: text ?? CompanionLines.statsWeekday(ml: point.averageML, weekdayText: calendar.weekdaySymbols[weekday - 1], seed: taps),
                            mood: .calm, progress: goalML > 0 ? point.averageML / goalML : 0)
        }
        guard let day = pin.day, let point = report.points.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) else { return nil }
        let dayText = point.day.formatted(.dateTime.weekday(.abbreviated).day().month())
        let line: String = switch pin.kind {
        case .caffeine: CompanionLines.statsCaffeine(mg: point.caffeineMg, dayText: dayText, seed: taps)
        case .alcohol: CompanionLines.statsAlcohol(standardDrinks: point.standardDrinks, dayText: dayText, seed: taps)
        default: CompanionLines.statsDay(ml: point.ml, goalML: goalML, dayText: dayText, seed: taps)
        }
        return DropSpot(kind: pin.kind, day: point.day, text: text ?? line,
                        mood: CompanionLogic.dayMood(standardDrinks: point.standardDrinks, caffeineMg: point.caffeineMg),
                        progress: goalML > 0 ? (point.ml ?? 0) / goalML : 0)
    }

    /// Average over days where the value isn't zero.
    private func average(_ values: [Double]) -> Double {
        let nonZero = values.filter { $0 > 0 }
        return nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
    }

    private func trendText(_ change: Double?) -> String {
        guard let change else { return "–" }
        return "\(change >= 0 ? "+" : "")\(Int(change.rounded())) %"
    }

    private func trendSymbol(_ change: Double?) -> String {
        guard let change else { return "chart.line.flattrend.xyaxis" }
        return change >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
    }
}
