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
