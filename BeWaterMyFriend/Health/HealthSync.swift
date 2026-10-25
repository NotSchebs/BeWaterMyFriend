import Foundation
import HealthKit
import Observation
import SwiftData

/// Writes logged drinks to Apple Health and removes them again after edits or deletes.
///
/// Every sample carries the entry's sync ID in its metadata. To update an entry,
/// all samples with that ID are deleted and the current version is written again.
/// HealthKit only lets an app delete samples it saved itself, so other apps' data
/// is never touched.
///
/// Apple documentation this relies on:
/// - Authorization: https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:)
/// - Saving: https://developer.apple.com/documentation/healthkit/hkhealthstore/save(_:withcompletion:)
/// - Deleting own samples by metadata:
///   https://developer.apple.com/documentation/healthkit/hkhealthstore/deleteobjects(of:predicate:withcompletion:)
///   https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(withmetadatakey:allowedvalues:)
/// - Drink name on samples: https://developer.apple.com/documentation/healthkit/hkmetadatakeyfoodtype
@MainActor
@Observable
final class HealthSync {
    static let shared = HealthSync()

    /// Custom metadata key holding the entry's sync ID (custom keys must not start with "HK").
    static let entryIDKey = "BeWaterMyFriendEntryID"

    private let store = HKHealthStore()
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSync: Date?
    /// Plain-language result of the last sync, shown in Settings.
    private(set) var lastResult: String?
    /// Increases after every "write now", so the UI can react (haptic, checkmark).
    private(set) var manualSyncCount = 0
    /// A "write now" request that arrived while a sync was running.
    private var forceRequested = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission to write every type this app can write.
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: Set(HealthQuantity.all.map(Self.sampleType)), read: [])
    }

    /// True once the user has answered the permission screen.
    /// https://developer.apple.com/documentation/healthkit/hkhealthstore/statusforauthorizationrequest(toshare:read:)
    func hasAnsweredPermission() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(
            toShare: Set(HealthQuantity.all.map(Self.sampleType)), read: [])
        return status == .unnecessary
    }

    /// Deletes Health samples of deleted entries, then writes entries whose
    /// delay has passed. `ignoreDelay` writes everything pending right away.
    func sync(context: ModelContext, delay: HealthWriteDelay, boundary: DayBoundary,
              ignoreDelay: Bool = false, now: Date = .now) async {
        guard isAvailable else { return }
        if isSyncing {
            // Don't drop a "write now" tap: run it right after the current sync.
            if ignoreDelay { forceRequested = true }
            return
        }
        // Take the lock *before* the first `await`. Otherwise two syncs (e.g. a
        // button tap and the save that follows it) can both get past the check
        // above while waiting, and both write the same drinks: duplicates.
        isSyncing = true
        var manual = ignoreDelay  // also true if a "write now" tap got queued
        defer {
            isSyncing = false
            if manual { manualSyncCount += 1 }
        }
        // Never sync while the permission screen is open or unanswered: every
        // type would look "not allowed" and nothing would be written.
        guard await hasAnsweredPermission() else {
            if ignoreDelay { lastResult = "Allow access to Apple Health first." }
            return
        }

        var force = ignoreDelay
        var written = 0
        do {
            if try await repairDuplicatesIfNeeded(context: context) { force = true }
            repeat {
                forceRequested = false
                for id in PendingHealthDeletes.all() {
                    try await deleteSamples(syncID: id)
                    PendingHealthDeletes.remove(id)
                }

                let entries = try context.fetch(FetchDescriptor<DrinkEntry>())
                let due = entries.filter {
                    $0.needsHealthWrite && (force || HealthPlan.isDue($0, delay: delay, boundary: boundary, now: now))
                }
                for entry in due {
                    if try await write(entry) { written += 1 }
                }
                if !due.isEmpty { try context.save() }
                force = true  // a queued request is always a "write now"
                if forceRequested { manual = true }
            } while forceRequested

            lastError = nil
            lastSync = now
            if manual || written > 0 {
                let pending = try context.fetch(FetchDescriptor<DrinkEntry>()).filter(\.needsHealthWrite).count
                lastResult = written > 0
                    ? "Wrote \(written) \(written == 1 ? "drink" : "drinks") to Apple Health."
                    : (pending == 0 ? "Nothing waiting. Apple Health is up to date." : "Some drinks couldn't be written. Check Health access in Settings.")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// One-time cleanup after the duplicate bug (fixed 25 Oct): deletes every
    /// sample this app ever wrote and marks all drinks as unwritten, so each is
    /// written exactly once again. Only this app's own data can be deleted.
    /// https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(from:)-7j3p2
    private func repairDuplicatesIfNeeded(context: ModelContext) async throws -> Bool {
        let key = "healthDuplicateRepairDone"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        let ownSamples = HKQuery.predicateForObjects(from: HKSource.default())
        for quantity in HealthQuantity.all {
            let type = Self.sampleType(quantity)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            _ = try await store.deleteObjects(of: type, predicate: ownSamples)
        }
        for id in PendingHealthDeletes.all() { PendingHealthDeletes.remove(id) }
        for entry in try context.fetch(FetchDescriptor<DrinkEntry>()) {
            entry.healthWrittenAt = nil
        }
        try context.save()
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    /// Returns false (entry stays pending) if Health access for one of its
    /// types hasn't been decided yet.
    private func write(_ entry: DrinkEntry) async throws -> Bool {
        let planned = HealthPlan.samples(for: entry)
        if planned.contains(where: { store.authorizationStatus(for: Self.sampleType($0.quantity)) == .notDetermined }) {
            return false
        }

        // Snapshot the version first: an edit during the async calls below stays pending.
        let version = entry.modifiedAt ?? entry.timestamp
        let id = entry.healthSyncID ?? UUID()
        // Always clear this drink's old samples first, so a write can never
        // leave two copies behind.
        if entry.healthSyncID != nil {
            try await deleteSamples(syncID: id)
        }

        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.name,
            Self.entryIDKey: id.uuidString,
        ]
        let samples: [HKQuantitySample] = planned.compactMap { planned in
            let type = Self.sampleType(planned.quantity)
            // Skip types the user turned off; saving them would fail the whole batch.
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: Self.unit(planned.quantity), doubleValue: planned.value),
                start: entry.timestamp,
                end: entry.timestamp,
                metadata: metadata
            )
        }
        if !samples.isEmpty {
            try await store.save(samples)
        }
        entry.healthSyncID = id
        entry.healthWrittenAt = version
        return true
    }

    /// Deletes every sample this app wrote for one entry.
    private func deleteSamples(syncID: UUID) async throws {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.entryIDKey,
                                                    allowedValues: [syncID.uuidString])
        for quantity in HealthQuantity.all {
            let type = Self.sampleType(quantity)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    // MARK: Mapping to HealthKit types and units

    private static func sampleType(_ quantity: HealthQuantity) -> HKQuantityType {
        HKQuantityType(identifier(quantity))
    }

    private static func unit(_ quantity: HealthQuantity) -> HKUnit {
        switch quantity.unit {
        case "ml": .literUnit(with: .milli)
        case "count": .count()
        case "g": .gram()
        case "mg": .gramUnit(with: .milli)
        case "µg": .gramUnit(with: .micro)
        case "kcal": .kilocalorie()
        default: fatalError("No HealthKit unit for \(quantity.unit)")
        }
    }

    // https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier
    private static func identifier(_ quantity: HealthQuantity) -> HKQuantityTypeIdentifier {
        switch quantity {
        case .water: .dietaryWater
        case .alcoholicBeverages: .numberOfAlcoholicBeverages
        case .nutrient(let nutrient):
            switch nutrient {
            case .caffeine: .dietaryCaffeine
            case .energy: .dietaryEnergyConsumed
            case .protein: .dietaryProtein
            case .carbohydrates: .dietaryCarbohydrates
            case .sugar: .dietarySugar
            case .fiber: .dietaryFiber
            case .fatTotal: .dietaryFatTotal
            case .fatSaturated: .dietaryFatSaturated
            case .fatMonounsaturated: .dietaryFatMonounsaturated
            case .fatPolyunsaturated: .dietaryFatPolyunsaturated
            case .cholesterol: .dietaryCholesterol
            case .sodium: .dietarySodium
            case .potassium: .dietaryPotassium
            case .calcium: .dietaryCalcium
            case .magnesium: .dietaryMagnesium
            case .iron: .dietaryIron
            case .zinc: .dietaryZinc
            case .phosphorus: .dietaryPhosphorus
            case .chloride: .dietaryChloride
            case .copper: .dietaryCopper
            case .manganese: .dietaryManganese
            case .selenium: .dietarySelenium
            case .chromium: .dietaryChromium
            case .molybdenum: .dietaryMolybdenum
            case .iodine: .dietaryIodine
            case .vitaminA: .dietaryVitaminA
            case .vitaminB6: .dietaryVitaminB6
            case .vitaminB12: .dietaryVitaminB12
            case .vitaminC: .dietaryVitaminC
            case .vitaminD: .dietaryVitaminD
            case .vitaminE: .dietaryVitaminE
            case .vitaminK: .dietaryVitaminK
            case .thiamin: .dietaryThiamin
            case .riboflavin: .dietaryRiboflavin
            case .niacin: .dietaryNiacin
            case .folate: .dietaryFolate
            case .biotin: .dietaryBiotin
            case .pantothenicAcid: .dietaryPantothenicAcid
            }
        }
    }
}
