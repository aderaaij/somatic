import SwiftUI
import WorkoutKit

struct TrainingCalendarView: View {
    @ObservedObject var scheduleManager: WorkoutScheduleManager
    @ObservedObject var workoutManager: WorkoutManager
    let scheduledWorkouts: [ScheduledWorkoutPlan]
    @Binding var selectedDate: Date?

    @State private var resolvedSelectedDate: Date = Date()

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Refresh card
                VStack(alignment: .leading, spacing: 8) {
                    RefreshWorkoutsContent(scheduleManager: scheduleManager)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Week strip
                WeekStripView(
                    timelineItems: timelineItemsByDay,
                    selectedDate: $resolvedSelectedDate
                )
                .padding(.bottom, 8)

                // Selected day's workouts
                DayDetailSection(
                    date: resolvedSelectedDate,
                    items: selectedDayItems,
                    workoutManager: workoutManager
                )
                .padding(.top, 4)
            }
            .padding(.vertical)
        }
        .onAppear {
            resolvedSelectedDate = selectedDate ?? Date()
            workoutManager.fetchAllRecentWorkouts()
        }
        .onChange(of: resolvedSelectedDate) { _, newValue in
            selectedDate = newValue
        }
    }

    // MARK: - Merged Data

    private var timelineItemsByDay: [DateComponents: [TrainingTimelineItem]] {
        var dict: [DateComponents: [TrainingTimelineItem]] = [:]

        for plan in scheduledWorkouts {
            let item = TrainingTimelineItem.scheduledPlan(plan)
            dict[item.dayComponents, default: []].append(item)
        }

        for summary in workoutManager.allWorkouts {
            let item = TrainingTimelineItem.pastWorkout(summary)
            dict[item.dayComponents, default: []].append(item)
        }

        for key in dict.keys {
            dict[key]?.sort { $0.date < $1.date }
        }

        return dict
    }

    private var selectedDayItems: [TrainingTimelineItem] {
        let dc = calendar.dateComponents([.year, .month, .day], from: resolvedSelectedDate)
        return timelineItemsByDay[dc] ?? []
    }
}

// MARK: - Day Detail Section

private struct DayDetailSection: View {
    let date: Date
    let items: [TrainingTimelineItem]
    @ObservedObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if items.isEmpty {
                Text("No workouts")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(items) { item in
                    timelineItemRow(item)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineItemRow(_ item: TrainingTimelineItem) -> some View {
        switch item {
        case .scheduledPlan(let plan):
            NavigationLink {
                ScheduledWorkoutDetailView(scheduled: plan)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        ScheduledWorkoutRow(scheduled: plan)
                        workoutStructureHint(plan)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        case .pastWorkout(let summary):
            NavigationLink {
                WorkoutDetailView(
                    summary: summary,
                    workoutManager: workoutManager
                )
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        WorkoutRow(
                            summary: summary,
                            status: workoutManager.extractionStatuses[summary.id]
                        )
                        pastWorkoutMetrics(summary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Scheduled Workout Hint

    @ViewBuilder
    private func workoutStructureHint(_ plan: ScheduledWorkoutPlan) -> some View {
        if case .custom(let custom) = plan.plan.workout {
            let parts = buildStructureParts(custom)
            if !parts.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(parts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 40)
            }
        }
    }

    private func buildStructureParts(_ custom: CustomWorkout) -> [String] {
        var parts: [String] = []
        if custom.warmup != nil { parts.append("Warmup") }
        for block in custom.blocks {
            let stepCount = block.steps.count
            if block.iterations > 1 {
                parts.append("\(block.iterations)x \(stepCount) steps")
            } else {
                parts.append("\(stepCount) step\(stepCount == 1 ? "" : "s")")
            }
        }
        if custom.cooldown != nil { parts.append("Cooldown") }
        return parts
    }

    // MARK: - Past Workout Metrics

    @ViewBuilder
    private func pastWorkoutMetrics(_ summary: WorkoutSummary) -> some View {
        if let distance = summary.distance, distance > 0 {
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Pace: \(formatPace(duration: summary.duration, distance: distance))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 40)
        }
    }

    private func formatPace(duration: TimeInterval, distance: Double) -> String {
        guard distance > 0 else { return "--" }
        let paceSecondsPerKm = duration / (distance / 1000)
        let minutes = Int(paceSecondsPerKm) / 60
        let seconds = Int(paceSecondsPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds)) /km"
    }
}
