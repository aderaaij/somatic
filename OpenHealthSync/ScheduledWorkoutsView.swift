//
//  ScheduledWorkoutsView.swift
//  OpenHealthSync
//
//  Displays scheduled workout plans and provides a button
//  to fetch new workouts from the training API queue.
//

import SwiftUI
import WorkoutKit
import HealthKit

struct ScheduledWorkoutsView: View {
    @ObservedObject var scheduleManager: WorkoutScheduleManager
    @State private var showRemoveAllConfirmation = false

    var body: some View {
        List {
            refreshStatusSection
            workoutListSection
        }
        .navigationTitle("Workout Plans")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !scheduleManager.scheduledWorkouts.isEmpty {
                    Button("Remove All", role: .destructive) {
                        showRemoveAllConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove all scheduled workouts?",
            isPresented: $showRemoveAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                Task {
                    await scheduleManager.removeAll()
                }
            }
        }
        .task {
            await scheduleManager.loadScheduledWorkouts()
        }
        .overlay {
            if scheduleManager.scheduledWorkouts.isEmpty && scheduleManager.refreshState == .idle {
                ContentUnavailableView(
                    "No Workout Plans",
                    systemImage: "figure.run.circle",
                    description: Text("Tap \"Check for New Workouts\" to fetch plans from your coach.")
                )
            }
        }
    }

    // MARK: - Refresh Status

    private var refreshStatusSection: some View {
        Section {
            Button {
                Task {
                    await scheduleManager.refreshFromServer()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Check for New Workouts")
                    Spacer()
                    refreshIndicator
                }
            }
            .disabled(scheduleManager.refreshState == .fetching || isScheduling)

            if case .done(let count) = scheduleManager.refreshState {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(count == 0 ? "No new workouts" : "\(count) workout\(count == 1 ? "" : "s") scheduled")
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = scheduleManager.refreshState {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var refreshIndicator: some View {
        switch scheduleManager.refreshState {
        case .fetching:
            ProgressView()
                .controlSize(.small)
        case .scheduling(let current, let total):
            Text("\(current)/\(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var isScheduling: Bool {
        if case .scheduling = scheduleManager.refreshState { return true }
        return false
    }

    // MARK: - Workout List

    @ViewBuilder
    private var workoutListSection: some View {
        if !scheduleManager.scheduledWorkouts.isEmpty {
            Section("Scheduled") {
                ForEach(scheduleManager.scheduledWorkouts, id: \.self) { scheduled in
                    ScheduledWorkoutRow(scheduled: scheduled)
                }
            }
        }
    }
}

// MARK: - Row

struct ScheduledWorkoutRow: View {
    let scheduled: ScheduledWorkoutPlan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(workoutName)
                    .font(.subheadline.weight(.medium))
                if let dateString = formattedDate {
                    Text(dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if scheduled.complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private var workoutName: String {
        switch scheduled.plan.workout {
        case .custom(let custom):
            return custom.displayName ?? "Custom Workout"
        case .goal(let goal):
            return "Goal: \(goal.activity.name)"
        case .pacer(let pacer):
            return "Pacer: \(pacer.activity.name)"
        case .swimBikeRun:
            return "Swim-Bike-Run"
        @unknown default:
            return "Workout"
        }
    }

    private var formattedDate: String? {
        let dc = scheduled.date
        guard let year = dc.year, let month = dc.month, let day = dc.day else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = dc.hour
        components.minute = dc.minute

        guard let date = Calendar.current.date(from: components) else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = dc.hour != nil ? .short : .none
        return formatter.string(from: date)
    }
}

// MARK: - HKWorkoutActivityType name helper

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        default: return "Workout"
        }
    }
}
