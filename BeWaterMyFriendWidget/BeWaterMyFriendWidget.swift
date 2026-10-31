import SwiftUI
import WidgetKit

nonisolated struct DrinkEntryForWidget: TimelineEntry, Sendable {
    var date: Date
    var state: WidgetState
}

/// One picture now, and new ones when the mood fades or the next day starts.
/// `nonisolated`: WidgetKit calls this off the main thread (see Color(light:dark:)).
nonisolated struct DrinkTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DrinkEntryForWidget {
        DrinkEntryForWidget(date: .now, state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DrinkEntryForWidget) -> Void) {
        Task { @MainActor in
            completion(Self.entry(at: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DrinkEntryForWidget>) -> Void) {
        Task { @MainActor in
            var entries = [Self.entry(at: .now)]
            // Follow the changes we can foresee, a few steps ahead.
            while entries.count < 5, let next = entries.last?.state.nextChange {
                entries.append(Self.entry(at: next))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    @MainActor
    private static func entry(at date: Date) -> DrinkEntryForWidget {
        DrinkEntryForWidget(date: date, state: WidgetState.make(snapshot: WidgetStore.snapshot(),
                                                                pending: WidgetStore.pending(), now: date))
    }
}

struct DrinkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var state: WidgetState

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallWidgetView(state: state)
            case .systemMedium: MediumWidgetView(state: state)
            default: LargeWidgetView(state: state)
            }
        }
        .padding(12)
        .fontDesign(.rounded)
        .containerBackground(Dojo.card, for: .widget)
    }
}

struct BeWaterMyFriendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BeWaterMyFriendWidget", provider: DrinkTimelineProvider()) { entry in
            DrinkWidgetView(state: entry.state)
        }
        .configurationDisplayName("Be Water")
        .description("Today's ring and your ninja drop, with your starred drinks one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct BeWaterMyFriendWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeWaterMyFriendWidget()
    }
}
