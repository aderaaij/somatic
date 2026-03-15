//
//  HealthManager.swift
//  OpenHealthSync
//
//  Created by Arden de Raaij on 14/03/2026.
//

import Foundation
import Combine
import OpenWearablesHealthSDK

// MARK: - Health Data Tiers

/// Data type tiers for incremental HealthKit authorization.
/// Core types are requested on first launch; additional tiers
/// can be enabled later from settings.
enum HealthDataTier: String, CaseIterable, Identifiable {
    case core
    case nutrition
    case clinical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .core: return "Activity & Fitness"
        case .nutrition: return "Nutrition"
        case .clinical: return "Clinical & Metabolic"
        }
    }

    var description: String {
        switch self {
        case .core: return "Steps, workouts, heart rate, sleep, and body measurements"
        case .nutrition: return "Calories, macronutrients, and hydration"
        case .clinical: return "Blood pressure, glucose, and advanced metrics"
        }
    }

    var types: [HealthDataType] {
        switch self {
        case .core:
            return [
                // Activity
                .steps,
                .activeEnergy,
                .basalEnergy,
                .distanceWalkingRunning,
                .distanceCycling,
                .flightsClimbed,
                // Heart & Cardio
                .heartRate,
                .restingHeartRate,
                .heartRateVariabilitySDNN,
                .vo2Max,
                .oxygenSaturation,
                .respiratoryRate,
                // Body
                .bodyMass,
                .height,
                .bmi,
                .bodyFatPercentage,
                .leanBodyMass,
                // Mobility
                .walkingSpeed,
                .walkingStepLength,
                // Sleep & Workout
                .sleep,
                .workout,
            ]
        case .nutrition:
            return [
                .dietaryEnergyConsumed,
                .dietaryProtein,
                .dietaryCarbohydrates,
                .dietaryFatTotal,
                .dietaryWater,
            ]
        case .clinical:
            return [
                .bloodGlucose,
                .bloodPressureSystolic,
                .bloodPressureDiastolic,
                .bodyTemperature,
                .walkingAsymmetryPercentage,
                .walkingDoubleSupportPercentage,
                .sixMinuteWalkTestDistance,
            ]
        }
    }
}

// MARK: - Sync Progress

enum TypeSyncStatus: Equatable {
    case pending
    case querying
    case syncing(samples: Int)
    case complete
    case skipped // already up to date
}

struct TypeSyncInfo: Identifiable, Equatable {
    let id: String // short type name, e.g. "stepcount"
    var displayName: String
    var status: TypeSyncStatus = .pending
    var sampleCount: Int = 0

    var isDone: Bool {
        status == .complete || status == .skipped
    }
}

@MainActor
class SyncProgress: ObservableObject {
    @Published var types: [TypeSyncInfo] = []
    @Published var isSyncing = false
    @Published var totalSent: Int = 0
    @Published var isFullExport = false

    var completedCount: Int { types.filter(\.isDone).count }
    var totalCount: Int { types.count }
    var fractionComplete: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var statusSummary: String {
        if !isSyncing && totalCount > 0 && completedCount == totalCount {
            return "Up to date"
        }
        if isSyncing {
            let mode = isFullExport ? "Initial sync" : "Syncing"
            return "\(mode) \(completedCount)/\(totalCount) types..."
        }
        return ""
    }

    func reset() {
        types.removeAll()
        isSyncing = false
        totalSent = 0
        isFullExport = false
    }

    /// Parse an SDK log message and update progress state.
    func processLog(_ message: String) {
        // Detect sync mode
        if message == "Full export" {
            isFullExport = true
            return
        }
        if message == "Incremental sync" {
            isFullExport = false
            return
        }

        // "Types to sync (N): type1, type2, ..."
        if message.hasPrefix("Types to sync") {
            if let colonIdx = message.firstIndex(of: ":"),
               colonIdx < message.endIndex {
                let namesStr = message[message.index(after: colonIdx)...]
                    .trimmingCharacters(in: .whitespaces)
                let names = namesStr.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                types = names.map { name in
                    TypeSyncInfo(
                        id: name,
                        displayName: formatTypeName(name)
                    )
                }
            }
            isSyncing = true
            return
        }

        // "Skipping typename - already synced"
        if message.hasPrefix("Skipping") && message.contains("already synced") {
            let typeName = message
                .replacingOccurrences(of: "Skipping ", with: "")
                .replacingOccurrences(of: " - already synced", with: "")
                .trimmingCharacters(in: .whitespaces)
            updateType(typeName) { info in
                info.status = .skipped
            }
            return
        }

        // "typename: querying..." or "typename: querying (newest first)..."
        if message.contains(": querying") {
            let typeName = extractTypeName(from: message)
            updateType(typeName) { info in
                info.status = .querying
            }
            return
        }

        // "  typename: complete" or "  typename: complete (anchor captured)"
        if message.contains(": complete") {
            let typeName = extractTypeName(from: message)
            updateType(typeName) { info in
                info.status = .complete
            }
            return
        }

        // "  typename: N samples" or "  typename: +N samples"
        if message.contains(" samples") && !message.contains("Sending") {
            let typeName = extractTypeName(from: message)
            if let count = extractSampleCount(from: message) {
                updateType(typeName) { info in
                    info.sampleCount += count
                    info.status = .syncing(samples: info.sampleCount)
                }
            }
            return
        }

        // "Sending X KB, N items:"
        if message.hasPrefix("Sending") && message.contains("items") {
            if let range = message.range(of: #"(\d+) items"#, options: .regularExpression) {
                let numStr = message[range].split(separator: " ").first ?? ""
                totalSent += Int(numStr) ?? 0
            }
            return
        }

        // Sync finished
        if message == "Sync cancelled" || message.contains("sync completed") ||
           message.contains("Sync incomplete") {
            isSyncing = false
            // Mark any remaining pending types as skipped (nothing to sync)
            for i in types.indices where types[i].status == .pending {
                types[i].status = .skipped
            }
        }
    }

    private func extractTypeName(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        if let colonIdx = trimmed.firstIndex(of: ":") {
            return String(trimmed[trimmed.startIndex..<colonIdx])
        }
        return trimmed
    }

    private func extractSampleCount(from message: String) -> Int? {
        let pattern = #"[+]?(\d+) samples"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return Int(message[range])
    }

    private func updateType(_ name: String, update: (inout TypeSyncInfo) -> Void) {
        if let idx = types.firstIndex(where: { $0.id == name }) {
            update(&types[idx])
        }
    }

    private func formatTypeName(_ name: String) -> String {
        var result = ""
        for (i, char) in name.enumerated() {
            if char.isUppercase && i > 0 {
                result += " "
            }
            result.append(i == 0 ? char.uppercased().first! : char)
        }
        return result
    }
}

// MARK: - Health Manager

@MainActor
class HealthManager: ObservableObject {
    @Published var status = "Not connected"
    @Published var logs: [String] = []
    @Published var enabledTiers: Set<HealthDataTier> = [.core, .nutrition]
    let syncProgress = SyncProgress()

    var onSyncCompleted: (() -> Void)?

    private let sdk = OpenWearablesHealthSDK.shared
    private var isConfigured = false

    /// Ensure the host has an https:// scheme.
    private func normalizeHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    /// Full setup: configure, sign in, request auth, and start syncing.
    func setup(host: String, userId: String, apiKey: String) {
        configureLogging()

        let normalizedHost = normalizeHost(host)
        sdk.configure(host: normalizedHost)
        sdk.signIn(
            userId: userId,
            accessToken: nil,
            refreshToken: nil,
            apiKey: apiKey
        )

        isConfigured = true
        status = "Connecting..."
        addLog("SDK configured for \(host)")
        requestAuthorizationAndSync()
    }

    /// Restore an existing session on app launch.
    /// Returns true if the session was restored successfully.
    func restoreSession(host: String) -> Bool {
        if isConfigured { return true }

        configureLogging()
        sdk.configure(host: normalizeHost(host))

        if let restoredUserId = sdk.restoreSession() {
            addLog("Session restored for user: \(restoredUserId)")
            isConfigured = true
            requestAuthorizationAndSync()
            return true
        } else {
            addLog("No valid session found")
            status = "Session expired"
            return false
        }
    }

    /// Sign out and clear SDK state.
    /// The caller is responsible for clearing @AppStorage values.
    func signOutAndReset() {
        sdk.signOut()
        isConfigured = false
        status = "Not connected"
        logs.removeAll()
        syncProgress.reset()
        addLog("Signed out")
    }

    /// Request authorization for all enabled tiers, then start syncing.
    func requestAuthorizationAndSync() {
        let allTypes = enabledTiers.flatMap { $0.types }

        status = "Requesting permissions..."
        addLog("Requesting HealthKit access for tiers: \(enabledTiers.map(\.rawValue).joined(separator: ", "))")

        sdk.requestAuthorization(types: allTypes) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.status = "Connected"
                    self?.addLog("HealthKit access granted, starting sync...")
                    self?.sdk.startBackgroundSync { started in
                        DispatchQueue.main.async {
                            self?.addLog("Background sync started: \(started)")
                        }
                    }
                } else {
                    self?.status = "Permission denied"
                    self?.addLog("HealthKit access denied")
                }
            }
        }
    }

    func syncNow() {
        sdk.syncNow { }
        addLog("Manual sync triggered")
    }

    func stopSync() {
        sdk.stopBackgroundSync()
        syncProgress.isSyncing = false
        status = "Connected"
        addLog("Sync stopped")
    }

    private func configureLogging() {
        guard !isConfigured else { return }

        sdk.onLog = { [weak self] message in
            DispatchQueue.main.async {
                self?.addLog(message)
                self?.syncProgress.processLog(message)

                if message.contains("sync completed") {
                    self?.onSyncCompleted?()
                }
            }
        }

        sdk.onAuthError = { [weak self] code, message in
            DispatchQueue.main.async {
                self?.status = "Auth error: \(code)"
                self?.addLog("Auth error: \(code) - \(message)")
            }
        }
    }

    private func addLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        logs.insert("[\(timestamp)] \(message)", at: 0)
    }
}
