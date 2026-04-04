import SwiftUI

struct MainTabView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var scheduleManager: WorkoutScheduleManager
    @ObservedObject var missedWorkoutDetector: MissedWorkoutDetector

    @AppStorage("openWearablesEnabled") private var openWearablesEnabled = false

    var body: some View {
        TabView {
            Tab("Training", systemImage: "figure.run.circle") {
                NavigationStack {
                    TrainingTabView(
                        scheduleManager: scheduleManager,
                        workoutManager: workoutManager,
                        missedWorkoutDetector: missedWorkoutDetector
                    )
                }
            }

            Tab("Settings", systemImage: "gearshape") {
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
