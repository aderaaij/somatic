import SwiftUI

// MARK: - Shared Content

/// The refresh button and status indicators, usable in any container.
struct RefreshWorkoutsContent: View {
    @ObservedObject var scheduleManager: WorkoutScheduleManager

    var body: some View {
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
}

// MARK: - List Section Wrapper

/// Wraps `RefreshWorkoutsContent` in a `Section` for use inside a `List`.
struct RefreshWorkoutsSection: View {
    @ObservedObject var scheduleManager: WorkoutScheduleManager

    var body: some View {
        Section {
            RefreshWorkoutsContent(scheduleManager: scheduleManager)
        }
    }
}
