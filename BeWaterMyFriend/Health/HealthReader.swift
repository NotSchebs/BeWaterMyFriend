import Foundation
import HealthKit

/// Reads body weight and today's workouts from Apple Health for the suggested goal.
/// Read-only; HealthKit never tells an app whether reading was allowed, so
/// "no data" and "not allowed" look the same (both return nil / 0).
///
/// Apple documentation this relies on:
/// - https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass
/// - https://developer.apple.com/documentation/healthkit/hkobjecttype/workouttype()
/// - https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor
/// - https://developer.apple.com/documentation/healthkit/hkquery/predicateforsamples(withstart:end:options:)
@MainActor
final class HealthReader {
    static let shared = HealthReader()

    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let workouts = HKObjectType.workoutType()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestReadAccess(weight: Bool, workouts readWorkouts: Bool) async {
        guard isAvailable else { return }
        var types: Set<HKObjectType> = []
        if weight { types.insert(bodyMass) }
        if readWorkouts { types.insert(workouts) }
        guard !types.isEmpty else { return }
        try? await store.requestAuthorization(toShare: [], read: types)
    }

    /// The most recent weight in kg, or nil.
    func latestWeightKg() async -> Double? {
        guard isAvailable else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    /// Total workout minutes within the interval (e.g. today's logical day).
    func workoutMinutes(in interval: DateInterval) async -> Double {
        guard isAvailable else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        )
        let found = (try? await descriptor.result(for: store)) ?? []
        return found.reduce(0) { $0 + $1.duration } / 60
    }
}
