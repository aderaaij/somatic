//
//  DebugWorkoutSeeder.swift
//  OpenHealthSync
//
//  DEBUG-only HealthKit seeder for the simulator: writes ~6 months of
//  realistic runs (distance, energy, heart-rate series, GPS route around
//  Lisbon) plus weekly strength sessions, so the workout list, detail charts,
//  and splits all have data without a real watch.
//
//  The whole file is compiled out of Release builds. By default seeded
//  workouts are marked as already-synced (same UserDefaults key
//  WorkoutManager uses) because BackgroundSyncManager auto-uploads anything
//  unsent — seeding must not push fake runs to a real account. Untick the
//  toggle in Settings → Developer only when signed into a test account.
//

#if DEBUG

import Foundation
import Combine
import HealthKit
import CoreLocation

@MainActor
final class DebugWorkoutSeeder: ObservableObject {
    @Published var isWorking = false
    @Published var statusMessage: String?

    private let healthStore = HKHealthStore()

    private static let heartRateType = HKQuantityType(.heartRate)
    private static let distanceType = HKQuantityType(.distanceWalkingRunning)
    private static let energyType = HKQuantityType(.activeEnergyBurned)

    private static let shareTypes: Set<HKSampleType> = [
        HKWorkoutType.workoutType(),
        heartRateType,
        distanceType,
        energyType,
        HKSeriesType.workoutRoute(),
    ]

    // Praça do Comércio-ish riverside start point.
    private static let startCoordinate = CLLocationCoordinate2D(latitude: 38.7075, longitude: -9.1364)

    // MARK: - Seeding

    /// Seeds ~26 weeks of workouts: three runs a week (one weekly long run)
    /// and a strength session every other week.
    func seed(markAsSynced: Bool) async {
        isWorking = true
        statusMessage = "Requesting HealthKit write access…"
        defer { isWorking = false }

        do {
            try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: [])

            var rng = SystemRandomNumberGenerator()
            var seededIDs: [UUID] = []
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let weeks = 26

            for week in 0..<weeks {
                statusMessage = "Seeding week \(week + 1) of \(weeks)…"

                // Mon / Wed / Sat pattern, anchored back from today.
                for (index, dayOffset) in [1, 3, 6].enumerated() {
                    guard let day = calendar.date(byAdding: .day, value: -(week * 7 + dayOffset), to: today),
                          day < Date() else { continue }
                    let isLongRun = index == 2
                    let km = isLongRun
                        ? Double.random(in: 12...18, using: &rng)
                        : Double.random(in: 5...9, using: &rng)
                    let start = calendar.date(byAdding: .minute,
                                              value: 7 * 60 + Int.random(in: 0...150, using: &rng),
                                              to: day)!
                    if let id = try await seedRun(start: start, km: km, rng: &rng) {
                        seededIDs.append(id)
                    }
                }

                if week.isMultiple(of: 2) {
                    if let day = calendar.date(byAdding: .day, value: -(week * 7 + 2), to: today),
                       day < Date() {
                        let start = calendar.date(byAdding: .hour, value: 18, to: day)!
                        if let id = try await seedStrength(start: start, rng: &rng) {
                            seededIDs.append(id)
                        }
                    }
                }
            }

            if markAsSynced {
                markSent(seededIDs)
            }
            statusMessage = "Seeded \(seededIDs.count) workouts\(markAsSynced ? " (marked as synced)" : "")."
        } catch {
            statusMessage = "Seeding failed: \(error.localizedDescription)"
        }
    }

    /// One outdoor run: paced distance + energy + HR samples and a GPS
    /// out-and-back route along the Tejo.
    private func seedRun(start: Date, km: Double, rng: inout SystemRandomNumberGenerator) async throws -> UUID? {
        let paceSecPerKm = Double.random(in: 315...400, using: &rng)   // 5:15–6:40 /km
        let duration = km * paceSecPerKm
        let end = start.addingTimeInterval(duration)
        let speed = km * 1000 / duration                               // m/s

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []

        // Distance + energy in 30s slices (gives the extractor real splits).
        let slice: TimeInterval = 30
        var t: TimeInterval = 0
        while t < duration {
            let sliceEnd = min(t + slice, duration)
            let sliceMeters = speed * (sliceEnd - t) * Double.random(in: 0.92...1.08, using: &rng)
            let sliceKcal = (sliceMeters / 1000) * 65
            samples.append(HKQuantitySample(
                type: Self.distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: sliceMeters),
                start: start.addingTimeInterval(t),
                end: start.addingTimeInterval(sliceEnd)
            ))
            samples.append(HKQuantitySample(
                type: Self.energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: sliceKcal),
                start: start.addingTimeInterval(t),
                end: start.addingTimeInterval(sliceEnd)
            ))
            t = sliceEnd
        }

        // HR every 15s: warmup ramp to a steady band + noise.
        let steadyHR = Double.random(in: 145...162, using: &rng)
        samples.append(contentsOf: heartRateSamples(
            start: start, duration: duration, warmupFrom: 105, steady: steadyHR, rng: &rng
        ))

        try await builder.addSamples(samples)
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { return nil }

        // Out-and-back route: east along the river, then retrace.
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        try await routeBuilder.insertRouteData(routeLocations(
            start: start, duration: duration, speed: speed, rng: &rng
        ))
        try await routeBuilder.finishRoute(with: workout, metadata: nil)

        return workout.uuid
    }

    /// One indoor strength session: energy + HR only, no distance/route.
    private func seedStrength(start: Date, rng: inout SystemRandomNumberGenerator) async throws -> UUID? {
        let duration = TimeInterval(Int.random(in: 35...55, using: &rng) * 60)
        let end = start.addingTimeInterval(duration)

        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = [
            HKQuantitySample(
                type: Self.energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: duration / 60 * 5.5),
                start: start,
                end: end
            ),
        ]
        samples.append(contentsOf: heartRateSamples(
            start: start, duration: duration, warmupFrom: 90,
            steady: Double.random(in: 115...135, using: &rng), rng: &rng
        ))

        try await builder.addSamples(samples)
        try await builder.endCollection(at: end)
        return try await builder.finishWorkout()?.uuid
    }

    private func heartRateSamples(start: Date, duration: TimeInterval,
                                  warmupFrom: Double, steady: Double,
                                  rng: inout SystemRandomNumberGenerator) -> [HKSample] {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let warmup = min(300.0, duration / 4)
        var samples: [HKSample] = []
        var t: TimeInterval = 0
        while t < duration {
            let base = t < warmup
                ? warmupFrom + (steady - warmupFrom) * (t / warmup)
                : steady
            let bpm = base + Double.random(in: -4...4, using: &rng)
            let at = start.addingTimeInterval(t)
            samples.append(HKQuantitySample(
                type: Self.heartRateType,
                quantity: HKQuantity(unit: bpmUnit, doubleValue: bpm),
                start: at,
                end: at
            ))
            t += 15
        }
        return samples
    }

    private func routeLocations(start: Date, duration: TimeInterval, speed: Double,
                                rng: inout SystemRandomNumberGenerator) -> [CLLocation] {
        let interval: TimeInterval = 15
        let halfway = duration / 2
        let metersPerDegreeLat = 111_111.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(Self.startCoordinate.latitude * .pi / 180)

        var locations: [CLLocation] = []
        var t: TimeInterval = 0
        while t <= duration {
            // Distance from start along the out-and-back line.
            let along = t <= halfway ? speed * t : speed * (duration - t)
            let wiggle = sin(t / 40) * 25 + Double.random(in: -6...6, using: &rng)
            locations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: Self.startCoordinate.latitude + wiggle / metersPerDegreeLat,
                    longitude: Self.startCoordinate.longitude + along / metersPerDegreeLon
                ),
                altitude: 8,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                timestamp: start.addingTimeInterval(t)
            ))
            t += interval
        }
        return locations
    }

    // MARK: - Sent tracking

    /// Same key WorkoutManager uses, so BackgroundSyncManager's auto-extract
    /// skips the seeded workouts instead of uploading them.
    private func markSent(_ ids: [UUID]) {
        let key = "sentWorkoutUUIDs"
        var sent = UserDefaults.standard.stringArray(forKey: key) ?? []
        sent.append(contentsOf: ids.map(\.uuidString).filter { !sent.contains($0) })
        UserDefaults.standard.set(sent, forKey: key)
    }

    // MARK: - Deletion

    /// Deletes every sample this app wrote to HealthKit (workouts, HR,
    /// distance, energy, routes). Real watch/phone data has a different
    /// source and is untouched.
    func deleteSeeded() async {
        isWorking = true
        statusMessage = "Deleting app-written HealthKit data…"
        defer { isWorking = false }

        do {
            try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: [])
            let ownSource = HKQuery.predicateForObjects(from: HKSource.default())
            var total = 0
            for type in Self.shareTypes {
                total += try await deleteObjects(of: type, predicate: ownSource)
            }
            statusMessage = "Deleted \(total) app-written samples."
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func deleteObjects(of type: HKSampleType, predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.deleteObjects(of: type, predicate: predicate) { _, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }
}

#endif
