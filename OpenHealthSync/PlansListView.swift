//
//  PlansListView.swift
//  OpenHealthSync
//
//  Browses every training plan grouped into Current, Upcoming, and Archived,
//  with a tappable detail view per plan.
//

import SwiftUI
import WorkoutKit

struct PlansListView: View {
    @ObservedObject var scheduleManager: WorkoutScheduleManager

    private func plans(_ lifecycle: PlanLifecycle) -> [TrainingPlan] {
        let matching = scheduleManager.allPlans.filter { $0.lifecycle == lifecycle }
        switch lifecycle {
        case .current, .upcoming:
            // Soonest first.
            return matching.sorted { startKey($0) < startKey($1) }
        case .archived:
            // Most recently ended first (fall back to start date when open-ended).
            return matching.sorted { endKey($0) > endKey($1) }
        }
    }

    private func startKey(_ plan: TrainingPlan) -> Date {
        plan.start ?? Date.distantFuture
    }

    private func endKey(_ plan: TrainingPlan) -> Date {
        plan.end ?? plan.start ?? Date.distantPast
    }

    var body: some View {
        List {
            section(for: .current)
            section(for: .upcoming)
            section(for: .archived)
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if scheduleManager.allPlans.isEmpty {
                await scheduleManager.loadAllPlans()
            }
        }
        .refreshable {
            await scheduleManager.loadAllPlans()
        }
        .overlay {
            if scheduleManager.allPlans.isEmpty {
                if scheduleManager.isLoadingPlans {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No Plans",
                        systemImage: "calendar.badge.clock",
                        description: Text("Training plans you create will appear here.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func section(for lifecycle: PlanLifecycle) -> some View {
        let group = plans(lifecycle)
        if !group.isEmpty {
            Section(lifecycle.label) {
                ForEach(group) { plan in
                    NavigationLink {
                        PlanDetailView(plan: plan, scheduleManager: scheduleManager)
                    } label: {
                        PlanRow(plan: plan)
                    }
                }
            }
        }
    }
}

// MARK: - Row

struct PlanRow: View {
    let plan: TrainingPlan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: PlanFormat.icon(for: plan.activityType))
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let dateRange = PlanFormat.dateRange(plan) {
                    Text(dateRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(trailingDetail)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private var trailingDetail: String {
        switch plan.lifecycle {
        case .current:
            if let week = plan.currentWeek, let total = plan.totalWeeks {
                return "Week \(week + 1)/\(total)"
            }
            return "Current"
        case .upcoming:
            if let start = plan.start {
                return "Starts \(PlanFormat.short.string(from: start))"
            }
            return "Upcoming"
        case .archived:
            if let total = plan.totalWeeks {
                return "\(total) wk"
            }
            return "Archived"
        }
    }
}

// MARK: - Detail

struct PlanDetailView: View {
    let plan: TrainingPlan
    @ObservedObject var scheduleManager: WorkoutScheduleManager

    @State private var workouts: [PlanWorkout] = []
    @State private var isLoading = true

    private var sortedWorkouts: [PlanWorkout] {
        workouts.sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }

    var body: some View {
        List {
            Section {
                PlanOverviewCard(
                    plan: plan,
                    planWorkouts: workouts,
                    scheduledWorkouts: scheduleManager.scheduledWorkouts
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let goals = plan.metadata?.goals, !goals.isEmpty {
                Section("Goals") {
                    ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                        GoalRow(goal: goal)
                    }
                }
            }

            if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Loading workouts…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !sortedWorkouts.isEmpty {
                Section("Workouts (\(sortedWorkouts.count))") {
                    ForEach(sortedWorkouts) { workout in
                        PlanWorkoutRow(workout: workout)
                    }
                }
            }

            if let background = plan.metadata?.background, !background.isEmpty {
                Section("Background") {
                    Text(background)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Reuse already-loaded workouts when viewing the active plan.
            if plan.id == scheduleManager.activePlan?.id, !scheduleManager.planWorkouts.isEmpty {
                workouts = scheduleManager.planWorkouts
                isLoading = false
            } else {
                workouts = await scheduleManager.workouts(forPlan: plan.id)
                isLoading = false
            }
        }
    }
}

// MARK: - Detail Rows

private struct GoalRow: View {
    let goal: PlanGoal

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private var text: String {
        if let description = goal.description, !description.isEmpty {
            return description
        }
        var parts = [goal.type.replacingOccurrences(of: "_", with: " ").capitalized]
        if let target = goal.target {
            parts.append([target.displayString, goal.unit].compactMap { $0 }.joined(separator: " "))
        }
        if let byWeek = goal.byWeek {
            parts.append("by week \(byWeek + 1)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct PlanWorkoutRow: View {
    let workout: PlanWorkout

    private var isCompleted: Bool { workout.status == "completed" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? Color.green : Color.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline)
                    .foregroundStyle(isCompleted ? .primary : .secondary)
                if let date = workout.scheduledDate {
                    Text(PlanFormat.medium.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Formatting Helpers

enum PlanFormat {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    static func dateRange(_ plan: TrainingPlan) -> String? {
        if let start = plan.start, let end = plan.end {
            return "\(short.string(from: start)) – \(short.string(from: end))"
        }
        if let start = plan.start {
            return "From \(short.string(from: start))"
        }
        return nil
    }

    static func icon(for activityType: String) -> String {
        switch activityType.lowercased() {
        case "running", "run": return "figure.run"
        case "cycling", "bike", "biking": return "figure.outdoor.cycle"
        case "swimming", "swim": return "figure.pool.swim"
        case "walking", "walk": return "figure.walk"
        case "hiking", "hike": return "figure.hiking"
        default: return "figure.run.circle"
        }
    }
}
