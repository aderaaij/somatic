//
//  OpenHealthSyncApp.swift
//  OpenHealthSync
//
//  Created by Arden de Raaij on 13/03/2026.
//

import SwiftUI
import WorkoutKit
import OpenWearablesHealthSDK

@main
struct SomaticApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var health = HealthManager()
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var scheduleManager = WorkoutScheduleManager(apiClient: WorkoutAPIClient())

    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("userId") private var userId: String = ""

    var body: some Scene {
        WindowGroup {
            if serverURL.isEmpty {
                NavigationStack {
                    ServerConfigView(mode: .onboarding) { url, user, key in
                        serverURL = url
                        userId = user
                        health.setup(host: url, userId: user, apiKey: key)
                    }
                }
            } else {
                MainTabView(health: health, workoutManager: workoutManager, scheduleManager: scheduleManager)
                    .onAppear {
                        if !health.restoreSession(host: serverURL) {
                            serverURL = ""
                            userId = ""
                        }
                        health.onSyncCompleted = { [weak workoutManager] in
                            Task {
                                await workoutManager?.extractNewWorkouts()
                            }
                        }
                    }
                    .task {
                        await scheduleManager.requestAuthorization()
                        await scheduleManager.loadScheduledWorkouts()
                    }
            }
        }
    }
}
