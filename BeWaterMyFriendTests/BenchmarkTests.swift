import SwiftData
import XCTest
@testable import BeWaterMyFriend

/// Storage and speed with years of data. Slow, so it only runs when
/// BWMF_BENCHMARK is set (e.g. TEST_RUNNER_BWMF_BENCHMARK=1 xcodebuild test).
@MainActor
final class BenchmarkTests: XCTestCase {
    func testTenYearsOfDrinks() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BWMF_BENCHMARK"] == nil, "benchmark only on request")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -10, to: calendar.startOfDay(for: .now))!

        // 10 drinks a day for 10 years; every third with caffeine, some with nutrients (like scans).
        var nutrients = Nutrients()
        nutrients.caffeineMg = 40
        nutrients.sugarG = 10
        nutrients.sodiumMg = 12
        nutrients.energyKcal = 42
        let days = 3650
        let insertStart = Date.now
        for day in 0..<days {
            let base = calendar.date(byAdding: .day, value: day, to: start)!
            for i in 0..<10 {
                let entry = DrinkEntry(timestamp: base.addingTimeInterval(Double(8 + i) * 3600), name: i % 3 == 0 ? "Coffee" : "Water",
                                       category: i % 3 == 0 ? .coffee : .water, volumeML: 250,
                                       nutrientsPer100ml: i % 3 == 0 ? nutrients : Nutrients())
                entry.healthSyncID = UUID()
                // Realistic: logged (and last changed) at its own time, written to Health then.
                entry.modifiedAt = entry.timestamp
                entry.healthWrittenAt = entry.timestamp
                context.insert(entry)
            }
            if day % 365 == 0 { try context.save() }
        }
        try context.save()
        let insertTime = Date.now.timeIntervalSince(insertStart)

        // Checkpoint the write-ahead log so the file size is the real size.
        let size = ["", "-wal", "-shm"].reduce(0) { total, suffix in
            total + ((try? FileManager.default.attributesOfItem(atPath: url.path + suffix)[.size] as? Int) ?? 0)
        }

        // What the Today screen does on every update: daily summaries over everything.
        let all = try context.fetch(FetchDescriptor<DrinkEntry>())
        let summaryStart = Date.now
        let summaries = Summaries.daily(entries: all, boundary: DayBoundary())
        let summaryTime = Date.now.timeIntervalSince(summaryStart)

        let fetchStart = Date.now
        _ = try context.fetch(FetchDescriptor<DrinkEntry>())
        let fetchTime = Date.now.timeIntervalSince(fetchStart)

        // New path: archive built once, then each update only looks at recent days.
        let boundary = DayBoundary()
        let today = boundary.logicalDay(for: .now)
        let limit = DojoArchive.archiveLimit(today: today, calendar: boundary.calendar)
        let archiveStart = Date.now
        let archive = DojoArchive().advanced(through: limit, days: summaries.filter { $0.day <= limit },
                                             goalML: 2000, calendar: boundary.calendar)
        let archiveTime = Date.now.timeIntervalSince(archiveStart)
        let cutoff = Calendar.current.date(byAdding: .day, value: -(DojoArchive.liveDays + 3), to: .now)!
        let updateStart = Date.now
        let recent = try context.fetch(FetchDescriptor<DrinkEntry>(predicate: #Predicate { $0.timestamp >= cutoff }))
        _ = DojoProgress.stats(recentDays: Summaries.daily(entries: recent, boundary: boundary), archive: archive,
                               goalML: 2000, today: today, calendar: boundary.calendar)
        let updateTime = Date.now.timeIntervalSince(updateStart)
        let healthStart = Date.now
        let candidates = try context.fetch(HealthSync.candidates(now: .now))
        let healthTime = Date.now.timeIntervalSince(healthStart)
        print("BENCHMARK new: archive once \(String(format: "%.2f", archiveTime)) s, each update \(String(format: "%.3f", updateTime)) s (\(recent.count) drinks), health check \(String(format: "%.3f", healthTime)) s (\(candidates.count) candidates)")

        print("""
        BENCHMARK 10 years: \(all.count) drinks, \(summaries.count) days
        BENCHMARK store size: \(size / 1024) KB (\(String(format: "%.0f", Double(size) / Double(all.count))) bytes per drink)
        BENCHMARK insert: \(String(format: "%.1f", insertTime)) s, fetch all: \(String(format: "%.2f", fetchTime)) s, daily summaries: \(String(format: "%.2f", summaryTime)) s
        """)
        XCTAssertEqual(all.count, days * 10)
        XCTAssertLessThan(size, 100 * 1024 * 1024, "10 years should stay far below 100 MB")
    }
}
