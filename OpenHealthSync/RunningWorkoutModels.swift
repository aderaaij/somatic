//
//  RunningWorkoutModels.swift
//  OpenHealthSync
//
//  Created by Arden de Raaij on 14/03/2026.
//

import Foundation

// MARK: - Extraction Status

enum WorkoutExtractionStatus: Equatable {
    case notExtracted
    case extracting
    case sending
    case sent(Date)
    case failed(String)
}

// MARK: - Detailed Workout

struct DetailedWorkout: Codable, Sendable {
    let id: UUID
    let planWorkoutId: UUID?
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalDistance: Double?             // meters
    let totalEnergyBurned: Double?        // kcal
    let source: String
    let route: [RoutePoint]?
    let heartRate: [TimeSeries]?          // bpm
    let cadence: [TimeSeries]?            // steps/min
    let power: [TimeSeries]?              // watts
    let speed: [TimeSeries]?              // m/s
    let strideLength: [TimeSeries]?       // meters
    let verticalOscillation: [TimeSeries]? // centimeters
    let groundContactTime: [TimeSeries]?  // milliseconds
    let splits: [Split]?
    let activities: [WorkoutActivityData]?  // structured intervals / multisport segments
    let events: [WorkoutEventData]?
    let metadata: [String: String]?
}

// MARK: - Route

struct RoutePoint: Codable, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
}

// MARK: - Time Series

struct TimeSeries: Codable, Sendable {
    let timestamp: Date
    let value: Double
}

// MARK: - Splits

struct Split: Codable, Sendable {
    let index: Int
    let distance: Double                  // meters
    let duration: TimeInterval            // seconds
    let pace: Double                      // seconds per km
    let averageHeartRate: Double?         // bpm
    let averageCadence: Double?           // steps/min
    let averagePower: Double?             // watts
    let elevationGain: Double?            // meters
    let elevationLoss: Double?            // meters
    let startDate: Date
    let endDate: Date
}

// MARK: - Workout Activities (intervals, multisport segments)

struct WorkoutActivityData: Codable, Sendable {
    let activityType: String              // e.g. "running", "transition"
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval            // seconds
    let totalDistance: Double?             // meters
    let totalEnergyBurned: Double?        // kcal
    let averageHeartRate: Double?         // bpm
    let events: [WorkoutEventData]?
    let metadata: [String: String]?
}

// MARK: - Workout Events

struct WorkoutEventData: Codable, Sendable {
    let type: String
    let startDate: Date
    let endDate: Date
    let metadata: [String: String]?
}

// MARK: - Workout Summary (for list display)

struct WorkoutSummary: Identifiable {
    let id: UUID
    let activityType: String
    let activityName: String
    let startDate: Date
    let duration: TimeInterval
    let distance: Double?
}
