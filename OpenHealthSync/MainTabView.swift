import SwiftUI

enum LBTab: Hashable {
    case training, settings
}

struct MainTabView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var scheduleManager: WorkoutScheduleManager
    @ObservedObject var missedWorkoutDetector: MissedWorkoutDetector

    @AppStorage("openWearablesEnabled") private var openWearablesEnabled = false

    @State private var tab: LBTab = .training

    var body: some View {
        ZStack(alignment: .bottom) {
            LB.bg.ignoresSafeArea()

            Group {
                switch tab {
                case .training:
                    NavigationStack {
                        TrainingTabView(
                            scheduleManager: scheduleManager,
                            workoutManager: workoutManager,
                            missedWorkoutDetector: missedWorkoutDetector
                        )
                    }
                case .settings:
                    NavigationStack {
                        SettingsTabView(
                            health: health,
                            workoutManager: workoutManager,
                            scheduleManager: scheduleManager,
                            openWearablesEnabled: openWearablesEnabled
                        )
                    }
                }
            }
            // Reserve room so scroll content clears the floating bar.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 64) }

            LBTabBar(selection: $tab)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Floating glass tab bar

struct LBTabBar: View {
    @Binding var selection: LBTab

    var body: some View {
        HStack(spacing: 6) {
            item(.training, icon: "figure.run", title: "Training")
            item(.settings, icon: "gearshape", title: "Settings")
        }
        .padding(7)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(LB.surfaceControl.opacity(0.35)))
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(LB.lineStrong, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 17, x: 0, y: 12)
    }

    private func item(_ value: LBTab, icon: String, title: String) -> some View {
        let on = selection == value
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
            Text(title)
                .font(.lbBody(14, .semibold))
        }
        .foregroundStyle(on ? LB.accent : LB.textTertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous).fill(on ? LB.accentTint() : .clear)
        )
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { selection = value }
        }
    }
}

// MARK: - Settings Tab

private struct SettingsTabView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var scheduleManager: WorkoutScheduleManager
    let openWearablesEnabled: Bool

    @AppStorage("trainingAPIBaseURL") private var storedBaseURL: String = ""
    @AppStorage("trainingAPIKey") private var storedAPIKey: String = ""

    var body: some View {
        ServerConfigView(
            mode: .settings,
            onSave: { baseURL, apiKey in
                // Config is persisted by ServerConfigView via @AppStorage
            },
            onSignOut: {
                storedBaseURL = ""
                storedAPIKey = ""
                if openWearablesEnabled {
                    health.signOutAndReset()
                }
            },
            onRemoveAllWorkouts: {
                await scheduleManager.removeAll()
            }
        )
    }
}
