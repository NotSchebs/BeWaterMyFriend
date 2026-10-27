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
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if companionEnabled, let insight = StatsInsight.sentence(report: report, entries: entries, calendar: boundary.calendar) {
                    Section {
                        HStack(spacing: 16) {
                            NinjaDrop(progress: report.goalRate, belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)),
                                      animated: false)
                                .frame(width: 40, height: 52)
                                .padding(.trailing, 12)
                            Text(insight)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
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
                    dailyChart(report)
                }

                if period == .month {
                    Section("Weekly average") {
                        weeklyChart(StatsCalculator.weeks(entries: entries, weeks: 8, goalML: goalML, today: today, boundary: boundary))
                    }
                }

                let weekdays = StatsCalculator.weekdays(report.points, calendar: boundary.calendar)
                if weekdays.count > 1 {
                    Section("By weekday") {
                        weekdayChart(weekdays, calendar: boundary.calendar)
                    }
                }

                if !report.tintTotals.isEmpty {
                    Section("What you drank") {
                        drinkTypeChart(report.tintTotals)
                    }
                }

                Section("Caffeine") {
                    perDayChart(report.points.map { ($0.day, $0.caffeineMg) }, color: DrinkTint.coffee.color, unit: "mg")
                    LabeledContent("In total", value: Format.mg(report.totalCaffeineMg))
                    LabeledContent("Per day with caffeine",
                                   value: Format.mg(average(report.points.map(\.caffeineMg))))
                }

                Section {
                    perDayChart(report.points.map { ($0.day, $0.standardDrinks) }, color: DrinkTint.beer.color, unit: "std. drinks")
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
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No stats yet", systemImage: "chart.bar",
                                           description: Text("Log drinks for a few days to see your trends."))
                }
            }
        }
    }

    // MARK: Charts

    private func dailyChart(_ report: StatsReport) -> some View {
        Chart {
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
        .frame(height: 200)
        .padding(.vertical, 6)
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

    private func weekdayChart(_ points: [WeekdayPoint], calendar: Calendar) -> some View {
        let symbols = calendar.shortWeekdaySymbols
        return Chart(points) { point in
            BarMark(x: .value("Weekday", symbols[point.weekday - 1]), y: .value("ml", point.averageML))
                .foregroundStyle(Dojo.water.gradient)
                .cornerRadius(4)
        }
        .frame(height: 160)
        .padding(.vertical, 6)
    }

    private func drinkTypeChart(_ totals: [TintTotal]) -> some View {
        HStack(spacing: 16) {
            Chart(totals, id: \.tint) { total in
                SectorMark(angle: .value("ml", total.ml), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(total.tint.ringColor)
                    .cornerRadius(3)
            }
            .frame(width: 120, height: 120)
            ColorLegend(totals: totals)
        }
        .padding(.vertical, 6)
    }

    /// Small bar chart per day (caffeine, alcohol).
    private func perDayChart(_ values: [(Date, Double)], color: Color, unit: String) -> some View {
        Chart(values, id: \.0) { day, value in
            BarMark(x: .value("Day", day, unit: .day), y: .value(unit, value))
                .foregroundStyle(color)
                .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxisLabel(unit)
        .frame(height: 110)
        .padding(.vertical, 6)
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
