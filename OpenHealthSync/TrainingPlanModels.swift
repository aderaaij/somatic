//
//  TrainingPlanModels.swift
//  OpenHealthSync
//
//  Created by Claude on 04/04/2026.
//

import Foundation

// MARK: - Training Plan

struct TrainingPlan: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let activityType: String
    let status: String
    let startDate: String
    let endDate: String
    let description: String?
    let metadata: TrainingPlanMetadata?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, description, metadata
        case activityType = "activity_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Parse startDate string to Date
    var start: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: startDate)
    }

    var end: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: endDate)
    }

    /// Current week number (0-indexed from start date)
    var currentWeek: Int? {
        guard let start else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, days / 7)
    }

    /// Total weeks in the plan
    var totalWeeks: Int? {
        guard let start, let end else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, (days / 7) + 1)
    }

    /// Current phase based on week number
    var currentPhase: PlanPhase? {
        guard let week = currentWeek else { return nil }
        return metadata?.phases?.first { $0.weeks.contains(week) }
    }
}

// MARK: - Plan Metadata

struct TrainingPlanMetadata: Codable, Sendable {
    let goals: [PlanGoal]?
    let guardrails: [String]?
    let phases: [PlanPhase]?
    let background: String?
    let athleteContext: AthleteContext?

    enum CodingKeys: String, CodingKey {
        case goals, guardrails, phases, background
        case athleteContext = "athlete_context"
    }
}

struct PlanGoal: Codable, Sendable {
    let type: String
    let target: Double?
    let unit: String?
    let byWeek: Int?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case type, target, unit, description
        case byWeek = "by_week"
    }
}

struct PlanPhase: Codable, Sendable, Identifiable {
    let name: String
    let weeks: [Int]
    let volumeTargetKm: Double?
    let notes: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, weeks, notes
        case volumeTargetKm = "volume_target_km"
    }
}

struct AthleteContext: Codable, Sendable {
    let age: Int?
    let fitnessLevel: String?
    let constraints: [String]?
    let riskFactors: [String]?

    enum CodingKeys: String, CodingKey {
        case age, constraints
        case fitnessLevel = "fitness_level"
        case riskFactors = "risk_factors"
    }
}

// MARK: - Plan Workout

struct PlanWorkout: Codable, Sendable, Identifiable {
    let id: UUID
    let activityType: String
    let title: String
    let description: String?
    let status: String
    let planId: UUID?
    let createdAt: String?
    /// Nil for legacy queue items inserted by the old backfill migration (pre ~2026-03-18).
    /// For those, fall back to WorkoutScheduleManager.scheduledDate(for:) which reads
    /// the iOS-side scheduledDateMap populated at schedule time.
    let scheduledDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case activityType = "activity_type"
        case planId = "plan_id"
        case createdAt = "created_at"
        case scheduledDate = "scheduled_date"
    }
}
