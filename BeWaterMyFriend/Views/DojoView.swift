import SwiftUI

/// The ninja drop's dojo: current belt, training stats and all belts.
struct DojoView: View {
    var progress: Double
    var belt: Belt
    var stats: DojoStats
    /// Goal days counted for belts (the highest ever reached).
    var goalDays: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        NinjaDrop(progress: progress, belt: belt)
                            .frame(width: 110, height: 145)
                            .padding(.top, 8)
                        Text(belt.title)
                            .font(.title2.bold())
                        HStack(spacing: 6) {
                            BeltBadge(belt: belt)
                            Text(belt.name).font(.subheadline)
                        }
                        if let next = belt.next {
                            let done = goalDays - belt.requiredGoalDays
                            let needed = next.requiredGoalDays - belt.requiredGoalDays
                            ProgressView(value: Double(done), total: Double(needed))
                                .tint(next.color == Belt.white.color ? Dojo.ink : next.color)
                                .padding(.horizontal)
                            Text("\(Format.count(needed - done, "more goal day", "more goal days")) to the \(next.name.lowercased())")
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

                Section {
                    ForEach(Belt.allCases, id: \.self) { item in
                        HStack(spacing: 12) {
                            BeltBadge(belt: item)
                                .scaleEffect(1.3)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
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
                } header: {
                    Text("Belts")
                } footer: {
                    Text("Earn belts on days you reach your water goal. Belts you've earned stay yours.")
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
        }
    }
}

/// Shown once when a new belt is earned.
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
            Text("New belt!")
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
    DojoView(progress: 0.7, belt: .orange, stats: DojoStats(goalDays: 9, currentStreak: 2, bestStreak: 5), goalDays: 9)
}

#Preview("Belt earned") {
    BeltEarnedView(belt: .green)
}
