import Foundation
import WorkoutKit

/// A unified representation of any workout-related item on the training timeline.
/// Wraps both WorkoutKit scheduled plans and HealthKit workout summaries.
enum TrainingTimelineItem: Identifiable {
    case scheduledPlan(ScheduledWorkoutPlan)
    case pastWorkout(WorkoutSummary)

    var id: String {
        switch self {
        case .scheduledPlan(let plan):
            return "plan-\(plan.hashValue)"
        case .pastWorkout(let summary):
            return "hk-\(summary.id.uuidString)"
        }
    }

    /// The canonical Date for sorting and day-grouping.
    var date: Date {
        switch self {
        case .scheduledPlan(let plan):
            return Calendar.current.date(from: plan.date) ?? .distantPast
        case .pastWorkout(let summary):
            return summary.startDate
        }
    }

    /// Day-level DateComponents for dictionary keying.
    var dayComponents: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    enum DotCategory {
        case upcomingPlan   // blue
        case completedPlan  // green
        case pastWorkout    // orange
    }

    var dotCategory: DotCategory {
        switch self {
        case .scheduledPlan(let plan):
            return plan.complete ? .completedPlan : .upcomingPlan
        case .pastWorkout:
            return .pastWorkout
        }
    }
}
