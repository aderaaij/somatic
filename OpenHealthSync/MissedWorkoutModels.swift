//
//  MissedWorkoutModels.swift
//  OpenHealthSync
//
//  SwiftData model for tracking missed workout feedback.
//  Stores the user's reason for missing and their chosen action
//  (reschedule, adjust plan, or skip).
//

import Foundation
import SwiftData

// MARK: - Enums

enum MissedWorkoutReason: String, Codable, CaseIterable, Identifiable {
    case busy
    case tired
    case weather
    case soreness
    case motivation
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .busy: return "Too busy"
        case .tired: return "Tired / low energy"
        case .weather: return "Weather"
        case .soreness: return "Sore / minor pain"
        case .motivation: return "Not feeling it"
        case .other: return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .busy: return "🗓️"
        case .tired: return "😴"
        case .weather: return "🌧️"
        case .soreness: return "🤕"
        case .motivation: return "😐"
        case .other: return "✏️"
        }
    }
}

enum MissedWorkoutAction: String, Codable, CaseIterable {
    case move
    case adjust
    case skip
}

// MARK: - SwiftData Model

@Model
final class WorkoutFeedback {
    var id: UUID
    var workoutId: UUID
    var workoutName: String
    var scheduledDate: Date
    var detectedAt: Date
    var acknowledgedAt: Date?
    var reason: MissedWorkoutReason
    var reasonNote: String?
    var action: MissedWorkoutAction
    var newDate: Date?
    var dismissed: Bool
    var synced: Bool = false

    init(
        workoutId: UUID,
        workoutName: String,
        scheduledDate: Date,
        reason: MissedWorkoutReason,
        action: MissedWorkoutAction,
        reasonNote: String? = nil,
        newDate: Date? = nil
    ) {
        self.id = UUID()
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.scheduledDate = scheduledDate
        self.detectedAt = Date()
        self.acknowledgedAt = Date()
        self.reason = reason
        self.reasonNote = reasonNote
        self.action = action
        self.newDate = newDate
        self.dismissed = false
        self.synced = false
    }
}

// MARK: - Lightweight Info for Detection

/// Non-persisted struct used by the detector to surface missed workouts to the UI.
struct MissedWorkoutInfo: Identifiable {
    let id: UUID          // the workout plan ID
    let displayName: String
    let scheduledDate: Date
}
