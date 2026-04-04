//
//  MissedWorkoutFeedbackSheet.swift
//  OpenHealthSync
//
//  Bottom sheet for collecting feedback when a workout is missed.
//  Two steps: reason picker (tappable chips) + action picker (3 CTAs).
//  Handles multi-miss batching by advancing through the queue.
//

import SwiftUI
import SwiftData

// MARK: - Feedback Flow (multi-workout wrapper)

struct MissedWorkoutFeedbackFlow: View {
    let missedWorkouts: [MissedWorkoutInfo]
    @ObservedObject var detector: MissedWorkoutDetector
    @EnvironmentObject private var scheduleManager: WorkoutScheduleManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0

    var body: some View {
        NavigationStack {
            if currentIndex < missedWorkouts.count {
                MissedWorkoutFeedbackSheet(
                    workout: missedWorkouts[currentIndex],
                    currentIndex: currentIndex + 1,
                    totalCount: missedWorkouts.count,
                    scheduleManager: scheduleManager,
                    onComplete: { handledWorkout in
                        // Remove from detector so banner/indicators update immediately
                        detector.missedWorkouts.removeAll { $0.id == handledWorkout.id }
                        advanceOrDismiss()
                    }
                )
            }
        }
        .interactiveDismissDisabled(false)
    }

    private func advanceOrDismiss() {
        let nextIndex = currentIndex + 1
        if nextIndex < missedWorkouts.count {
            currentIndex = nextIndex
        } else {
            dismiss()
        }
    }
}

// MARK: - Single Workout Feedback Sheet

struct MissedWorkoutFeedbackSheet: View {
    let workout: MissedWorkoutInfo
    let currentIndex: Int
    let totalCount: Int
    let scheduleManager: WorkoutScheduleManager
    let onComplete: (MissedWorkoutInfo) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: MissedWorkoutReason?
    @State private var reasonNote = ""
    @State private var showReschedulePicker = false
    @State private var showAdjustConfirmation = false
    @State private var isRescheduling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Reason picker
                reasonSection

                // "Other" text field
                if selectedReason == .other {
                    TextField("What happened?", text: $reasonNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .padding(.horizontal)
                }

                // Action buttons
                if selectedReason != nil {
                    actionSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Check in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showReschedulePicker) {
            RescheduleDatePicker(
                workout: workout,
                onConfirm: { newDate in
                    saveFeedback(action: .move, newDate: newDate)
                    isRescheduling = true
                    Task {
                        let success = await scheduleManager.rescheduleWorkout(
                            id: workout.id,
                            to: newDate
                        )
                        isRescheduling = false
                        if !success {
                            print("Failed to reschedule workout \(workout.id) to \(newDate)")
                        }
                        onComplete(workout)
                    }
                }
            )
        }
        .overlay {
            if showAdjustConfirmation {
                adjustConfirmationOverlay
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if totalCount > 1 {
                Text("\(currentIndex) of \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.displayName)
                        .font(.headline)
                    Text(workout.scheduledDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Reason Picker

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What happened?")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal)

            FlowLayout(spacing: 8) {
                ForEach(MissedWorkoutReason.allCases) { reason in
                    ReasonChip(
                        reason: reason,
                        isSelected: selectedReason == reason
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedReason = reason
                            if reason != .other {
                                reasonNote = ""
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to do?")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal)

            VStack(spacing: 8) {
                actionButton(
                    title: "Reschedule",
                    subtitle: "Move to another day",
                    icon: "calendar.badge.clock",
                    style: .prominent
                ) {
                    showReschedulePicker = true
                }

                actionButton(
                    title: "Adjust plan",
                    subtitle: "We'll bring this up next time you review your plan",
                    icon: "arrow.triangle.branch",
                    style: .secondary
                ) {
                    saveFeedback(action: .adjust)
                    showAdjustConfirmation = true
                }

                actionButton(
                    title: "Skip this one",
                    subtitle: "No changes needed",
                    icon: "forward.fill",
                    style: .secondary
                ) {
                    saveFeedback(action: .skip)
                    onComplete(workout)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Adjust Confirmation Overlay

    private var adjustConfirmationOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Got it")
                .font(.headline)
            Text("We'll bring this up next time you review your plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .background(.regularMaterial)
        .cornerRadius(20)
        .padding(40)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showAdjustConfirmation = false
                onComplete(workout)
            }
        }
    }

    // MARK: - Save

    private func saveFeedback(action: MissedWorkoutAction, newDate: Date? = nil) {
        guard let reason = selectedReason else { return }

        let feedback = WorkoutFeedback(
            workoutId: workout.id,
            workoutName: workout.displayName,
            scheduledDate: workout.scheduledDate,
            reason: reason,
            action: action,
            reasonNote: reason == .other ? reasonNote : nil,
            newDate: newDate
        )
        modelContext.insert(feedback)

        // Fire-and-forget sync to training API
        let payload = WorkoutFeedbackPayload(
            id: feedback.id,
            workoutId: feedback.workoutId,
            workoutName: feedback.workoutName,
            scheduledDate: feedback.scheduledDate,
            detectedAt: feedback.detectedAt,
            acknowledgedAt: feedback.acknowledgedAt,
            reason: feedback.reason.rawValue,
            reasonNote: feedback.reasonNote,
            action: feedback.action.rawValue,
            newDate: feedback.newDate,
            dismissed: feedback.dismissed
        )
        scheduleManager.syncFeedback(payload, feedbackId: feedback.id, modelContext: modelContext)
    }

    // MARK: - Action Button Helper

    private enum ActionButtonStyle { case prominent, secondary }

    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        style: ActionButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 32)
                    .foregroundStyle(style == .prominent ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(style == .prominent ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reason Chip

private struct ReasonChip: View {
    let reason: MissedWorkoutReason
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(reason.emoji)
                    .font(.callout)
                Text(reason.label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .cornerRadius(20)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

/// A simple flow layout that wraps chips to the next line when they don't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangementResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return ArrangementResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: currentY + lineHeight)
        )
    }
}

// MARK: - Previews

#Preview("Feedback Sheet") {
    let workout = MissedWorkoutInfo(
        id: UUID(),
        displayName: "Easy 6K",
        scheduledDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    )

    NavigationStack {
        MissedWorkoutFeedbackSheet(
            workout: workout,
            currentIndex: 1,
            totalCount: 1,
            scheduleManager: WorkoutScheduleManager(apiClient: WorkoutAPIClient()),
            onComplete: { _ in }
        )
    }
    .modelContainer(for: WorkoutFeedback.self, inMemory: true)
}
