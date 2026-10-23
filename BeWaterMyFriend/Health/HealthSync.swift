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

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission to write every type this app can write.
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: Set(HealthQuantity.all.map(Self.sampleType)), read: [])
    }

    /// Deletes Health samples of deleted entries, then writes entries whose
    /// delay has passed. `ignoreDelay` writes everything pending right away.
    func sync(context: ModelContext, delay: HealthWriteDelay, boundary: DayBoundary,
              ignoreDelay: Bool = false, now: Date = .now) async {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            for id in PendingHealthDeletes.all() {
                try await deleteSamples(syncID: id)
                PendingHealthDeletes.remove(id)
            }

            let entries = try context.fetch(FetchDescriptor<DrinkEntry>())
            let due = entries.filter {
                $0.needsHealthWrite && (ignoreDelay || HealthPlan.isDue($0, delay: delay, boundary: boundary, now: now))
            }
            for entry in due {
                try await write(entry)
            }
            if !due.isEmpty { try context.save() }
            lastError = nil
            lastSync = now
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func write(_ entry: DrinkEntry) async throws {
        // Snapshot the version first: an edit during the async calls below stays pending.
        let version = entry.modifiedAt ?? entry.timestamp
        let id = entry.healthSyncID ?? UUID()
        if entry.healthWrittenAt != nil {
            try await deleteSamples(syncID: id)
        }

        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.name,
            Self.entryIDKey: id.uuidString,
        ]
        let samples: [HKQuantitySample] = HealthPlan.samples(for: entry).compactMap { planned in
            let type = Self.sampleType(planned.quantity)
            // Skip types the user didn't allow; saving them would fail the whole batch.
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
