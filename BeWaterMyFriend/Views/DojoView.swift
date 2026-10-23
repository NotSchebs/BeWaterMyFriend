import SwiftUI

/// The ninja drop's dojo: current rank, training stats, all belts and Dan
/// ranks, and the optional prestige once the 10th Dan is reached.
struct DojoView: View {
    var progress: Double
    var layers: [FillLayer]
    var mood: CompanionMood
    var belt: Belt
    var stats: DojoStats
    /// Goal days counted for ranks (the highest ever reached, since the last prestige).
    var goalDays: Int
    var prestige: Int
    var onPrestige: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmPrestige = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(
                            ZStack {
                                Dojo.card
                                SeigaihaPattern().opacity(0.08)
                            }
                        )
                }

                Section("Training") {
                    HStack {
                        StatTile(title: "Goal days", value: "\(goalDays)", symbol: "checkmark.seal.fill")
                        StatTile(title: "Streak", value: "\(stats.currentStreak)", symbol: "flame.fill")
                        StatTile(title: "Best streak", value: "\(stats.bestStreak)", symbol: "trophy.fill")
                    }
                    .padding(.vertical, 4)
                }

                Section("Belts") {
                    ForEach(Belt.allCases.filter { !$0.isDan }, id: \.self) { item in
                        rankRow(item)
                    }
                }

                Section {
                    ForEach(Belt.allCases.filter(\.isDan), id: \.self) { item in
                        rankRow(item)
                    }
                } header: {
                    Text("Dan ranks")
                } footer: {
                    Text(belt.isDan || belt == .black
                         ? "Black belt is only the beginning."
                         : "Unlock after the black belt. Black belt is only the beginning.")
                }

                if DojoProgress.canPrestige(belt) {
                    Section {
                        Button("Begin again with prestige ★\(prestige + 1)") {
                            confirmPrestige = true
                        }
                        .foregroundStyle(Dojo.seal)
                    } footer: {
                        Text("Start the ranks again at white belt and earn a permanent prestige seal. Your history and goal days are kept.")
                    }
                }
            }
            .dojoBackground()
            .navigationTitle("Dojo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Start again at white belt?", isPresented: $confirmPrestige, titleVisibility: .visible) {
                Button("Begin again", role: .destructive) {
                    onPrestige()
                    dismiss()
                }
            } message: {
                Text("You'll get the prestige seal ★\(prestige + 1) and keep it forever. Your drinks, history and goal days stay; only the ranks start over.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            NinjaDrop(progress: progress, belt: belt, layers: layers, mood: mood, prestige: prestige)
                .frame(width: 110, height: 145)
                .padding(.top, 8)
            Text(belt.title)
                .font(.title2.bold())
            HStack(spacing: 6) {
                BeltBadge(belt: belt)
                Text([belt.name, belt.japaneseName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                if prestige > 0 {
                    Text("★\(prestige)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Dojo.seal)
                }
            }
            if let next = belt.next {
                let done = goalDays - belt.requiredGoalDays
                let needed = next.requiredGoalDays - belt.requiredGoalDays
                ProgressView(value: Double(max(done, 0)), total: Double(needed))
                    .tint(next == .white ? Dojo.ink : next.color)
                    .padding(.horizontal)
                Text("\(Format.count(needed - done, "more goal day", "more goal days")) to \(next.isDan ? "" : "the ")\(next.isDan ? next.name : next.name.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Highest rank reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func rankRow(_ item: Belt) -> some View {
        HStack(spacing: 12) {
            BeltBadge(belt: item)
                .scaleEffect(1.3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text([item.name, item.japaneseName].compactMap { $0 }.joined(separator: " · "))
                Text(item == .white ? item.title : "\(item.title) · \(item.requiredGoalDays) goal days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item <= belt {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Dojo.seal)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(item <= belt ? 1 : 0.6)
    }
}

/// Shown once when a new rank is earned.
struct BeltEarnedView: View {
    var belt: Belt
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                SeigaihaPattern().opacity(0.12).frame(width: 260, height: 180).mask(Circle())
                NinjaDrop(progress: 1, belt: belt)
                    .frame(width: 120, height: 158)
                    .scaleEffect(appear ? 1 : 0.4)
                    .rotationEffect(.degrees(appear ? 0 : -20))
            }
            Text(belt.isDan ? "New Dan rank!" : "New belt!")
                .font(.headline)
                .foregroundStyle(Dojo.seal)
            Text(belt.name)
                .font(.largeTitle.bold())
            Text("You are now a \(belt.title).")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Keep flowing")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Dojo.paper)
        .sensoryFeedback(.success, trigger: appear)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.5)) { appear = true }
        }
    }
}

#Preview("Dojo") {
    DojoView(progress: 0.7, layers: [FillLayer(tint: .water, fraction: 0.5), FillLayer(tint: .coffee, fraction: 0.2)],
             mood: .hyper, belt: .dan2, stats: DojoStats(goalDays: 210, currentStreak: 12, bestStreak: 40),
             goalDays: 210, prestige: 1, onPrestige: {})
}

#Preview("Belt earned") {
    BeltEarnedView(belt: .dan1)
}
