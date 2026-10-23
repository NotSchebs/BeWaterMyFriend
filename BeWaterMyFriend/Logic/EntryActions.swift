import Foundation
import SwiftData

/// Deleting entries goes through here so their Apple Health samples get
/// deleted too (on the next sync), not left behind as wrong data.
enum EntryActions {
    static func delete(_ entries: [DrinkEntry], in context: ModelContext, defaults: UserDefaults = .standard) {
        for entry in entries {
            if entry.healthWrittenAt != nil, let id = entry.healthSyncID {
                PendingHealthDeletes.add(id, defaults: defaults)
            }
            context.delete(entry)
        }
        try? context.save()
    }
}

/// Sync IDs of deleted entries whose Health samples still need deleting.
enum PendingHealthDeletes {
    private static let key = "pendingHealthDeletes"

    static func all(defaults: UserDefaults = .standard) -> [UUID] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    static func add(_ id: UUID, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: key) ?? []
        if !ids.contains(id.uuidString) { ids.append(id.uuidString) }
        defaults.set(ids, forKey: key)
    }

    static func remove(_ id: UUID, defaults: UserDefaults = .standard) {
        let ids = (defaults.stringArray(forKey: key) ?? []).filter { $0 != id.uuidString }
        defaults.set(ids, forKey: key)
    }
}
