//
//  MissedWorkoutBanner.swift
//  OpenHealthSync
//
//  Shows a card/banner on the Training tab when missed workouts
//  are detected. Tapping "Check in" opens the feedback sheet.
//

import SwiftUI
import SwiftData

struct MissedWorkoutBanner: View {
    @ObservedObject var detector: MissedWorkoutDetector
    @EnvironmentObject private var scheduleManager: WorkoutScheduleManager
    @Environment(\.modelContext) private var modelContext

    @State private var showFeedbackSheet = false

    var body: some View {
        if !detector.missedWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        if detector.missedWorkouts.count == 1, let workout = detector.missedWorkouts.first {
                            Text("You missed \(workout.displayName)")
                                .font(.subheadline.weight(.medium))
                            Text(relativeDate(workout.scheduledDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("You have \(detector.missedWorkouts.count) missed workouts")
                                .font(.subheadline.weight(.medium))
                            Text("Want to check in?")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        dismissAll()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showFeedbackSheet = true
                } label: {
                    Text("Check in")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(Color.orange.opacity(0.08))
            .cornerRadius(12)
            .padding(.horizontal)
            .sheet(isPresented: $showFeedbackSheet) {
                MissedWorkoutFeedbackFlow(
                    missedWorkouts: detector.missedWorkouts,
                    detector: detector
                )
            }
        }
    }

    private func dismissAll() {
        for workout in detector.missedWorkouts {
            detector.dismiss(workout: workout, modelContext: modelContext)

            // Sync dismissal to training API
            // Fetch the just-inserted feedback to get its ID for sync tracking
            let targetWorkoutId = workout.id
            let descriptor = FetchDescriptor<WorkoutFeedback>(
                predicate: #Predicate<WorkoutFeedback> { feedback in
                    feedback.workoutId == targetWorkoutId && feedback.dismissed == true
                },
                sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
            )
            if let inserted = try? modelContext.fetch(descriptor).first {
                let payload = WorkoutFeedbackPayload(
                    id: inserted.id,
                    workoutId: inserted.workoutId,
                    workoutName: inserted.workoutName,
                    scheduledDate: inserted.scheduledDate,
                    detectedAt: inserted.detectedAt,
                    acknowledgedAt: inserted.acknowledgedAt,
                    reason: inserted.reason.rawValue,
                    reasonNote: inserted.reasonNote,
                    action: inserted.action.rawValue,
                    newDate: inserted.newDate,
                    dismissed: inserted.dismissed
                )
                scheduleManager.syncFeedback(payload, feedbackId: inserted.id, modelContext: modelContext)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Scheduled \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
