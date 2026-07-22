//
//  TrendsModels.swift
//  OpenHealthSync
//
//  Wire model for GET /api/workouts/summary — per-period aggregates over the
//  full server-side workout history (the phone only keeps 6 months locally).
//  snake_case like the rest of the workouts resource family.
//
//  Marked `nonisolated` because the project defaults types to @MainActor
//  (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor); without this the Codable
//  conformance couldn't be used from the WorkoutAPIClient actor.
//

import Foundation

/// One aggregate row per (period, activity_type). Units are what the app
/// uploaded: meters, seconds, kcal. Aggregates are nullable — strength
/// sessions carry no distance.
///
/// `period` is NOT ISO8601 — it's a stringified Postgres `date_trunc` with a
/// space separator ("2026-07-01 00:00:00+00:00"), so it's kept as a String
/// and parsed via `periodStart`.
nonisolated struct ServerWorkoutSummaryRow: Decodable, Sendable {
    let period: String
    let activityType: String
    let count: Int
    let totalDistance: Double?
    let totalDuration: Double?
    let avgDistance: Double?
    let avgDuration: Double?
    let totalEnergyBurned: Double?

    enum CodingKeys: String, CodingKey {
        case period, count
        case activityType = "activity_type"
        case totalDistance = "total_distance"
        case totalDuration = "total_duration"
        case avgDistance = "avg_distance"
        case avgDuration = "avg_duration"
        case totalEnergyBurned = "total_energy_burned"
    }

    /// Start of the period, from the first 10 chars ("yyyy-MM-dd") of the
    /// date_trunc string. A fresh fixed-locale formatter per call keeps the
    /// type Sendable-safe.
    var periodStart: Date? {
        guard period.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(period.prefix(10)))
    }
}
