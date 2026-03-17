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

struct TrainingTabView: View {
    @ObservedObject var scheduleManager: WorkoutScheduleManager
    @ObservedObject var workoutManager: WorkoutManager
    @State private var showRemoveAllConfirmation = false
    @State private var viewMode: ViewMode = .timeline
    @State private var selectedDate: Date?

    enum ViewMode: String, CaseIterable {
        case timeline, list
    }

    private var upcomingWorkouts: [ScheduledWorkoutPlan] {
        scheduleManager.scheduledWorkouts
            .filter { !$0.complete }
            .sorted {
                let date0 = Calendar.current.date(from: $0.date) ?? .distantFuture
                let date1 = Calendar.current.date(from: $1.date) ?? .distantFuture
                return date0 < date1
            }
    }

    private var completedWorkouts: [ScheduledWorkoutPlan] {
        scheduleManager.scheduledWorkouts
            .filter { $0.complete }
            .sorted {
                let date0 = Calendar.current.date(from: $0.date) ?? .distantPast
                let date1 = Calendar.current.date(from: $1.date) ?? .distantPast
                return date0 > date1
            }
    }

    private var pastWorkouts: [WorkoutSummary] {
        workoutManager.allWorkouts.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        Group {
            switch viewMode {
            case .timeline:
                TrainingCalendarView(
                    scheduleManager: scheduleManager,
                    workoutManager: workoutManager,
                    scheduledWorkouts: scheduleManager.scheduledWorkouts,
                    selectedDate: $selectedDate
                )
            case .list:
                List {
                    RefreshWorkoutsSection(scheduleManager: scheduleManager)

                    if !upcomingWorkouts.isEmpty {
                        Section("Upcoming Plans") {
                            ForEach(upcomingWorkouts, id: \.self) { scheduled in
                                NavigationLink {
                                    ScheduledWorkoutDetailView(scheduled: scheduled)
                                } label: {
                                    ScheduledWorkoutRow(scheduled: scheduled)
                                }
                            }
                        }
                    }

                    if !completedWorkouts.isEmpty {
                        Section("Completed Plans") {
                            ForEach(completedWorkouts, id: \.self) { scheduled in
                                NavigationLink {
                                    ScheduledWorkoutDetailView(scheduled: scheduled)
                                } label: {
                                    ScheduledWorkoutRow(scheduled: scheduled)
                                }
                            }
                        }
                    }

                    if !pastWorkouts.isEmpty {
                        Section("Past Workouts") {
                            ForEach(pastWorkouts) { summary in
                                NavigationLink {
                                    WorkoutDetailView(
                                        summary: summary,
                                        workoutManager: workoutManager
                                    )
                                } label: {
                                    WorkoutRow(
                                        summary: summary,
                                        status: workoutManager.extractionStatuses[summary.id]
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Training")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View Mode", selection: $viewMode) {
                    Image(systemName: "calendar").tag(ViewMode.timeline)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
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
            workoutManager.fetchAllRecentWorkouts()
        }
        .overlay {
            if viewMode == .list
                && scheduleManager.scheduledWorkouts.isEmpty
                && workoutManager.allWorkouts.isEmpty
                && scheduleManager.refreshState == .idle {
                ContentUnavailableView(
                    "No Workouts",
                    systemImage: "figure.run.circle",
                    description: Text("Tap \"Check for New Workouts\" to fetch plans, or complete a workout to see it here.")
                )
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
