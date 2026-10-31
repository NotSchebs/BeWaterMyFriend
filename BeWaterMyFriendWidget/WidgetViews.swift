import AppIntents
import SwiftUI
import WidgetKit

/// The ring with the drink colours and the drop inside, as on the Today screen.
/// The drop is static: widgets can't animate.
private struct RingAndDrop: View {
    var state: WidgetState
    var diameter: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            ProgressRing(progress: state.progress, lineWidth: lineWidth, layers: state.layers)
            if state.showsDrop {
                NinjaDrop(progress: min(state.progress, 1), belt: state.belt, layers: state.layers,
                          mood: state.mood, prestige: state.prestige, animated: false)
                    .frame(width: diameter * 0.38, height: diameter * 0.5)
                    .offset(x: -diameter * 0.02)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// ★1, ★2 or ★3 on a button, when the drink is starred.
private struct StarNumber: View {
    var number: Int?

    var body: some View {
        if let number {
            HStack(spacing: 1) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("\(number)")
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 9))
        }
    }
}

/// A quick-log button as a list row.
private struct DrinkRowButton: View {
    var drink: WidgetDrink
    var position: Int

    var body: some View {
        Button(intent: LogQuickDrinkIntent(position: position)) {
            HStack(spacing: 6) {
                Image(systemName: drink.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(Dojo.ink)
                    .frame(width: 18)
                Text(drink.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                StarNumber(number: drink.starNumber)
                Text(Format.ml(drink.volumeML))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Dojo.ink.opacity(0.1), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(drink.name), \(Format.ml(drink.volumeML))")
    }
}

/// A quick-log button as a small tile.
private struct DrinkTileButton: View {
    var drink: WidgetDrink
    var position: Int
    var horizontal = false

    var body: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 3)) : AnyLayout(VStackLayout(spacing: 2))
        Button(intent: LogQuickDrinkIntent(position: position)) {
            layout {
                Image(systemName: drink.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(Dojo.ink)
                Text(Format.ml(drink.volumeML))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !horizontal { StarNumber(number: drink.starNumber) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Dojo.ink.opacity(0.1), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(drink.name), \(Format.ml(drink.volumeML))")
    }
}

/// The app's link for "+": the Add drink screen, which offers New drink and Scan.
let addDrinkURL = URL(string: "bewatermyfriend://add")!

/// The look of "+".
private struct PlusLabel: View {
    var label: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.footnote.weight(.bold))
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Dojo.ink, in: .rect(cornerRadius: 10))
        .accessibilityLabel("Add a drink")
    }
}

/// "+" on Medium and Large. iOS doesn't let a widget's button open the app, so
/// it's a link. The Small widget can't have links: see `SmallWidgetView`.
private struct PlusButton: View {
    var label: String? = nil

    var body: some View {
        Link(destination: addDrinkURL) { PlusLabel(label: label) }
    }
}

// MARK: Small

/// Ring, amount, then ★1 bottom left and "+" bottom right. Anywhere else opens the app.
struct SmallWidgetView: View {
    var state: WidgetState

    var body: some View {
        VStack(spacing: 4) {
            RingAndDrop(state: state, diameter: 76, lineWidth: 8)
            (Text(Format.ml(state.ml)).font(.caption.bold())
             + Text(" of \(Format.ml(state.goalML))").font(.system(size: 10)).foregroundStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let first = state.quickDrinks.first {
                    DrinkTileButton(drink: first, position: 0, horizontal: true)
                }
                PlusButton()
            }
            .frame(height: 30)
        }
    }
}

// MARK: Medium

/// Ring on the left, ★1 to ★3 and "+" on the right.
struct MediumWidgetView: View {
    var state: WidgetState

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                RingAndDrop(state: state, diameter: 92, lineWidth: 9)
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text(Format.ml(state.ml))
                        .font(.subheadline.bold())
                    Text("of \(Format.ml(state.goalML))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .frame(width: 110)
            VStack(spacing: 5) {
                ForEach(Array(state.quickDrinks.enumerated()), id: \.offset) { index, drink in
                    DrinkRowButton(drink: drink, position: index)
                }
                PlusButton(label: "New or scan")
            }
        }
    }
}

// MARK: Large

private struct StatColumn: View {
    var symbol: String
    var value: String
    var title: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(Dojo.ink)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Today screen in a widget. Every block has a fixed place, so it looks the
/// same after one glass and after a full day: the legend has room for three rows
/// and shows "+ more" beyond six drink types.
struct LargeWidgetView: View {
    var state: WidgetState

    private var shownTotals: [TintTotal] { Array(state.totals.prefix(6)) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                RingAndDrop(state: state, diameter: 118, lineWidth: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.ml(state.ml))
                        .font(.title2.bold())
                    Text("of \(Format.ml(state.goalML)) · \(Format.percent(state.progress))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if state.showsDrop {
                        Text(state.message)
                            .font(.caption)
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            legend
                .frame(height: 50)  // centered: few drinks don't leave a hole below

            HStack {
                StatColumn(symbol: "bolt.fill", value: Format.mg(state.caffeineMg), title: "Caffeine")
                StatColumn(symbol: "wineglass.fill", value: Format.standardDrinks(state.standardDrinks), title: "Std. drinks")
                StatColumn(symbol: "drop", value: Format.ml(state.totalFluidML), title: "All fluids")
            }

            HStack(spacing: 6) {
                ForEach(Array(state.quickDrinks.enumerated()), id: \.offset) { index, drink in
                    DrinkTileButton(drink: drink, position: index)
                }
                PlusButton()
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var legend: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(0..<(shownTotals.count + 1) / 2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        legendItem(index: row * 2 + column)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func legendItem(index: Int) -> some View {
        if index < shownTotals.count {
            let total = shownTotals[index]
            let isLastWithMore = index == 5 && state.totals.count > 6
            HStack(spacing: 4) {
                Circle().fill(total.tint.ringColor).frame(width: 8, height: 8)
                Text(total.tint.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                Text(isLastWithMore ? "+\(state.totals.count - 6) more" : Format.ml(total.ml))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }
}
