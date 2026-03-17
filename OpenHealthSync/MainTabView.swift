import SwiftUI

struct MainTabView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var scheduleManager: WorkoutScheduleManager

    var body: some View {
        TabView {
            Tab("Sync", systemImage: "arrow.up.circle") {
                NavigationStack {
                    SyncTabView(
                        health: health,
                        workoutManager: workoutManager
                    )
                }
            }

            Tab("Training", systemImage: "figure.run.circle") {
                NavigationStack {
                    TrainingTabView(
                        scheduleManager: scheduleManager,
                        workoutManager: workoutManager
                    )
                }
            }
        }
    }
}
