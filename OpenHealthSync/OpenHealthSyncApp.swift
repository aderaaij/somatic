//
//  OpenHealthSyncApp.swift
//  OpenHealthSync
//
//  Created by Arden de Raaij on 13/03/2026.
//

import SwiftUI
import SwiftData
import WorkoutKit
import OpenWearablesHealthSDK

@main
struct SomaticApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var health = HealthManager()
    @StateObject private var workoutManager: WorkoutManager
    @StateObject private var scheduleManager: WorkoutScheduleManager
    @StateObject private var missedWorkoutDetector = MissedWorkoutDetector()
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var backgroundSyncManager: BackgroundSyncManager

    @AppStorage("trainingAPIBaseURL") private var trainingAPIBaseURL: String = ""
    @AppStorage("trainingAPIKey") private var trainingAPIKey: String = ""
    @AppStorage("preferredRunTime") private var preferredRunTime: String = PreferredRunTime.morning.rawValue
    @AppStorage("openWearablesEnabled") private var openWearablesEnabled: Bool = false
    @AppStorage("healthMetricsSyncEnabled") private var healthMetricsSyncEnabled: Bool = true
    @AppStorage("serverURL") private var owServerURL: String = ""

    @Environment(\.scenePhase) private var scenePhase

    private let apiClient: WorkoutAPIClient
    private let healthMetricsSyncer: HealthMetricsSyncer

    init() {
        // Read persisted config, falling back to Info.plist values
        let info = Bundle.main.infoDictionary ?? [:]
        let storedURL = UserDefaults.standard.string(forKey: "trainingAPIBaseURL") ?? ""
        let storedKey = UserDefaults.standard.string(forKey: "trainingAPIKey") ?? ""
        let baseURL = storedURL.isEmpty ? (info["WorkoutAPIBaseURL"] as? String ?? "") : storedURL
        let apiKey = storedKey.isEmpty ? (info["WorkoutAPIKey"] as? String ?? "") : storedKey

        let client = WorkoutAPIClient(baseURL: baseURL, apiKey: apiKey)
        self.apiClient = client

        let syncer = HealthMetricsSyncer(apiClient: client)
        self.healthMetricsSyncer = syncer

        let wm = WorkoutManager()
        let sm = WorkoutScheduleManager(apiClient: client)
        wm.scheduleManager = sm
        _workoutManager = StateObject(wrappedValue: wm)
        _scheduleManager = StateObject(wrappedValue: sm)
        _backgroundSyncManager = StateObject(wrappedValue: BackgroundSyncManager(
            workoutManager: wm,
            healthMetricsSyncer: syncer
        ))
    }

    var body: some Scene {
        WindowGroup {
            if trainingAPIBaseURL.isEmpty {
                NavigationStack {
                    ServerConfigView(mode: .onboarding) { baseURL, apiKey in
                        trainingAPIBaseURL = baseURL
                        trainingAPIKey = apiKey
                        Task {
                            await apiClient.configure(
                                baseURL: URL(string: baseURL) ?? URL(string: "https://localhost")!,
                                apiKey: apiKey
                            )
                        }
                    }
                }
            } else {
                MainTabView(
                    health: health,
                    workoutManager: workoutManager,
                    scheduleManager: scheduleManager,
                    missedWorkoutDetector: missedWorkoutDetector
                )
                .environmentObject(scheduleManager)
                .onAppear {
                    // Restore OpenWearables session if enabled
                    if openWearablesEnabled && !owServerURL.isEmpty {
                        if !health.restoreSession(host: owServerURL) {
                            // Session restore failed — don't wipe Training API config
                        }
                        health.onSyncCompleted = { [weak workoutManager] in
                            Task {
                                await workoutManager?.extractNewWorkouts()
                            }
                        }
                    }
                    Task {
                        await notificationManager.requestPermission()
                    }
                }
                .task {
                    await scheduleManager.requestAuthorization()
                    await scheduleManager.loadScheduledWorkouts()
                    await scheduleManager.autoSync()
                    await scheduleManager.loadActivePlan()

                    // Request HealthKit auth for health metrics and set up background sync
                    if healthMetricsSyncEnabled {
                        _ = await healthMetricsSyncer.requestAuthorization()
                        try? await healthMetricsSyncer.syncMetrics()
                    }

                    // Register HealthKit background observers for automatic sync
                    await backgroundSyncManager.setUp()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await scheduleManager.loadScheduledWorkouts()
                            await scheduleManager.autoSync()
                            await detectAndNotify()

                            // Sync health metrics on foreground
                            if healthMetricsSyncEnabled {
                                try? await healthMetricsSyncer.syncMetrics()
                            }
                        }
                    }
                }
            }
        }
        .modelContainer(for: WorkoutFeedback.self)
    }

    private func detectAndNotify() async {
        guard let container = try? ModelContainer(for: WorkoutFeedback.self) else { return }
        let context = ModelContext(container)

        missedWorkoutDetector.checkForMissedWorkouts(
            scheduledWorkouts: scheduleManager.scheduledWorkouts,
            modelContext: context
        )

        if !missedWorkoutDetector.missedWorkouts.isEmpty {
            let runTime = PreferredRunTime(rawValue: preferredRunTime) ?? .morning
            await notificationManager.scheduleMissedWorkoutNotification(
                workouts: missedWorkoutDetector.missedWorkouts,
                preferredRunTime: runTime
            )
        } else {
            await notificationManager.cancelPendingMissedWorkoutNotifications()
        }
    }
}
