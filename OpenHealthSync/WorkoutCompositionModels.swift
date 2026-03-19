//
//  WorkoutCompositionModels.swift
//  OpenHealthSync
//
//  Codable models for workout compositions received from the training API queue.
//  These represent planned workouts that Claude creates, which get scheduled
//  on Apple Watch via WorkoutKit.
//

import Foundation

// MARK: - Queue Response

struct QueuedWorkoutComposition: Codable, Sendable, Identifiable {
    let id: UUID
    let displayName: String
    let activityType: String        // "running", "cycling", etc.
    let location: String            // "outdoor", "indoor"
    let scheduledDate: Date
    let warmup: CompositionStep?
    let blocks: [CompositionBlock]
    let cooldown: CompositionStep?
}

// MARK: - Block & Step

struct CompositionBlock: Codable, Sendable {
    let iterations: Int
    let steps: [CompositionIntervalStep]
}

struct CompositionIntervalStep: Codable, Sendable {
    let purpose: String             // "work" or "recovery"
    let goal: CompositionGoal
    let alert: CompositionAlert?
}

struct CompositionStep: Codable, Sendable {
    let goal: CompositionGoal
    let alert: CompositionAlert?
}

// MARK: - Goal

struct CompositionGoal: Codable, Sendable {
    let type: String                // "open", "distance", "time", "energy"
    let value: Double?
    let unit: String?               // "meters", "kilometers", "miles", "seconds", "minutes", "kilocalories"
}

// MARK: - Alert

struct CompositionAlert: Codable, Sendable {
    let type: String                // "speed", "heartRate", "heartRateZone", "cadence", "power", "powerZone"
    let min: Double?
    let max: Double?
    let zone: Int?
    let unit: String?               // "metersPerSecond", "kilometersPerHour", "beatsPerMinute", "stepsPerMinute", "watts"
}

// MARK: - Pending Actions (edit/delete from server)

struct PendingWorkoutAction: Codable, Sendable, Identifiable {
    let id: UUID                    // Action ID (for acknowledgement)
    let workoutId: UUID             // The workout plan UUID to act on
    let action: String              // "edit" or "delete"
    let composition: QueuedWorkoutComposition?  // Present only for "edit" actions
}

// MARK: - Workout Inventory (app → server sync)

/// Sent to the server so the LLM knows which workouts are currently scheduled
/// on-device, including legacy workouts that predate the queue system.
struct WorkoutInventoryItem: Codable, Sendable {
    let id: UUID
    let displayName: String
    let date: CodableDateComponents
    let complete: Bool

    init(id: UUID, displayName: String, date: DateComponents, complete: Bool) {
        self.id = id
        self.displayName = displayName
        self.date = CodableDateComponents(date)
        self.complete = complete
    }
}

// MARK: - Codable DateComponents Helper

/// Lightweight wrapper to persist DateComponents in UserDefaults via JSON.
struct CodableDateComponents: Codable {
    let year: Int?
    let month: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?

    init(_ dc: DateComponents) {
        self.year = dc.year
        self.month = dc.month
        self.day = dc.day
        self.hour = dc.hour
        self.minute = dc.minute
    }

    var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
