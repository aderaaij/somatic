//
//  PlanOverviewCard.swift
//  OpenHealthSync
//
//  Created by Claude on 04/04/2026.
//

import SwiftUI
import WorkoutKit

struct PlanOverviewCard: View {
    let plan: TrainingPlan
    let planWorkouts: [PlanWorkout]
    let scheduledWorkouts: [ScheduledWorkoutPlan]

    @State private var selectedPhase: PlanPhase?

    private var completedCount: Int {
        let planWorkoutIds = Set(planWorkouts.map { $0.id })
        return scheduledWorkouts.filter { $0.complete && planWorkoutIds.contains($0.plan.id) }.count
    }

    private var totalCount: Int {
        planWorkouts.count
    }

    private var completionFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Plan name and dates
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.subheadline.weight(.semibold))
                    if let start = plan.start, let end = plan.end {
                        Text("\(Self.dateFormatter.string(from: start)) – \(Self.dateFormatter.string(from: end))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(completedCount)/\(totalCount)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let currentWeek = plan.currentWeek, let totalWeeks = plan.totalWeeks {
                        Text("Week \(currentWeek + 1)/\(totalWeeks)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Progress bar
            ProgressView(value: completionFraction)
                .tint(.green)

            // Current phase
            if let phase = plan.currentPhase {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(phase.name)
                        .font(.caption.weight(.medium))
                    if let notes = phase.notes {
                        Text("· \(notes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Phase pills (tappable)
            if let phases = plan.metadata?.phases, !phases.isEmpty {
                phasePills(phases)
            }

            // Expanded phase detail
            if let phase = selectedPhase {
                phaseDetail(phase)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Phase Pills

    @ViewBuilder
    private func phasePills(_ phases: [PlanPhase]) -> some View {
        let currentWeek = plan.currentWeek ?? -1

        HStack(spacing: 4) {
            ForEach(phases) { phase in
                let isCurrent = phase.weeks.contains(currentWeek)
                let isCompleted = phase.weeks.allSatisfy { $0 < currentWeek }
                let isSelected = selectedPhase?.name == phase.name

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPhase = isSelected ? nil : phase
                    }
                } label: {
                    Text(phase.name)
                        .font(.caption2.weight(isCurrent || isSelected ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isSelected ? Color.blue.opacity(0.25) :
                            isCurrent ? Color.blue.opacity(0.15) :
                            isCompleted ? Color.green.opacity(0.1) :
                            Color.secondary.opacity(0.08)
                        )
                        .foregroundStyle(
                            isSelected ? .blue :
                            isCurrent ? .blue :
                            isCompleted ? .green :
                            .secondary
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Phase Detail

    @ViewBuilder
    private func phaseDetail(_ phase: PlanPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack {
                Text(phase.name)
                    .font(.caption.weight(.semibold))
                Spacer()
                if phase.weeks.count == 1 {
                    Text("Week \(phase.weeks[0] + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let first = phase.weeks.first, let last = phase.weeks.last {
                    Text("Weeks \(first + 1)–\(last + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let volume = phase.volumeTargetKm {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("Target: \(Int(volume)) km/week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let notes = phase.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Show workouts in this phase
            let phaseWorkouts = workoutsInPhase(phase)
            if !phaseWorkouts.isEmpty {
                VStack(spacing: 3) {
                    ForEach(phaseWorkouts) { workout in
                        HStack(spacing: 6) {
                            Image(systemName: workout.status == "completed" ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(workout.status == "completed" ? Color.green : Color.secondary.opacity(0.4))
                            Text(workout.title)
                                .font(.caption)
                                .foregroundStyle(workout.status == "completed" ? .primary : .secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// Find plan workouts that fall within a phase's week range.
    private func workoutsInPhase(_ phase: PlanPhase) -> [PlanWorkout] {
        guard let startDate = plan.start else { return [] }
        let calendar = Calendar.current

        return planWorkouts.filter { workout in
            // Match workout to inventory to get scheduled date
            guard let scheduled = scheduledWorkouts.first(where: { $0.plan.id == workout.id }),
                  let scheduledDate = calendar.date(from: scheduled.date) else {
                return false
            }
            let days = calendar.dateComponents([.day], from: startDate, to: scheduledDate).day ?? 0
            let week = max(0, days / 7)
            return phase.weeks.contains(week)
        }
    }
}

// MARK: - Loading Placeholder

struct PlanLoadingPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading training plan…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }
}
