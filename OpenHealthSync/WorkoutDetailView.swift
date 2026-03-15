//
//  WorkoutDetailView.swift
//  OpenHealthSync
//
//  Created by Arden de Raaij on 14/03/2026.
//

import SwiftUI
import HealthKit

// MARK: - Workout List

struct WorkoutListView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @State private var showResyncConfirmation = false
    @State private var isResyncing = false

    private let filterOptions: [(String, HKWorkoutActivityType?)] = [
        ("All", nil),
        ("Run", .running),
        ("Walk", .walking),
        ("Cycle", .cycling),
        ("Hike", .hiking),
        ("Swim", .swimming),
        ("Strength", .functionalStrengthTraining),
    ]

    var body: some View {
        List {
            if workoutManager.workouts.isEmpty {
                ContentUnavailableView(
                    "No Workouts",
                    systemImage: "figure.run",
                    description: Text("No \(filterLabel.lowercased()) workouts found.")
                )
            } else {
                ForEach(workoutManager.workouts) { summary in
                    NavigationLink {
                        WorkoutDetailView(
                            summary: summary,
                            workoutManager: workoutManager
                        )
                    } label: {
                        WorkoutRow(
                            summary: summary,
                            status: workoutManager.extractionStatuses[summary.id]
                        )
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showResyncConfirmation = true
                    } label: {
                        if isResyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Re-sync All", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isResyncing || workoutManager.workouts.isEmpty)

                    Menu {
                        ForEach(filterOptions, id: \.0) { label, type in
                            Button {
                                workoutManager.activeFilter = type
                                workoutManager.fetchRecentWorkouts()
                            } label: {
                                if workoutManager.activeFilter == type {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    } label: {
                        Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Re-sync all \(filterLabel.lowercased()) workouts?",
            isPresented: $showResyncConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-sync All (\(workoutManager.workouts.count) workouts)") {
                isResyncing = true
                Task {
                    await workoutManager.resyncAll()
                    isResyncing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will re-extract and re-send all workouts to the server.")
        }
        .onAppear {
            workoutManager.fetchRecentWorkouts()
        }
    }

    private var filterLabel: String {
        filterOptions.first(where: { $0.1 == workoutManager.activeFilter })?.0 ?? "All"
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {
    let summary: WorkoutSummary
    var status: WorkoutExtractionStatus?

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.activityName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(summary.startDate, style: .date)
                    if let distance = summary.distance {
                        Text(formatDistance(distance))
                    }
                    Text(formatDuration(summary.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            statusIndicator
        }
    }

    private var iconName: String {
        switch summary.activityType {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "hiking": return "figure.hiking"
        case "swimming": return "figure.pool.swim"
        case "yoga": return "figure.yoga"
        case "functionalStrength", "traditionalStrength": return "figure.strengthtraining.functional"
        case "coreTraining": return "figure.core.training"
        case "hiit": return "figure.highintensity.intervaltraining"
        case "cooldown": return "figure.cooldown"
        case "flexibility": return "figure.flexibility"
        case "pilates": return "figure.pilates"
        case "cardioDance", "socialDance": return "figure.dance"
        case "elliptical": return "figure.elliptical"
        case "rowing": return "figure.rower"
        case "crossTraining", "mixedCardio": return "figure.mixed.cardio"
        case "jumpRope": return "figure.jumprope"
        case "climbing": return "figure.climbing"
        case "boxing", "kickboxing": return "figure.boxing"
        case "tennis", "tableTennis", "badminton": return "figure.tennis"
        case "soccer": return "figure.soccer"
        case "basketball": return "figure.basketball"
        case "golf": return "figure.golf"
        case "snowboarding", "downhillSkiing", "snowSports": return "figure.snowboarding"
        case "crossCountrySkiing": return "figure.skiing.crosscountry"
        case "surfing": return "figure.surfing"
        case "mindAndBody": return "brain.head.profile"
        default: return "figure.mixed.cardio"
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .extracting, .sending:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        default:
            EmptyView()
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.2f km", km)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }
}

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let summary: WorkoutSummary
    @ObservedObject var workoutManager: WorkoutManager

    private var status: WorkoutExtractionStatus {
        workoutManager.extractionStatuses[summary.id] ?? .notExtracted
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Type", value: summary.activityName)
                LabeledContent("Date", value: summary.startDate.formatted(
                    date: .abbreviated, time: .shortened
                ))
                LabeledContent("Duration", value: formatDuration(summary.duration))
                if let distance = summary.distance {
                    LabeledContent("Distance", value: formatDistance(distance))
                    LabeledContent("Pace", value: formatPace(
                        duration: summary.duration, distance: distance
                    ))
                }
            }

            Section("Data Extraction") {
                extractionStatusRow
                extractButton
            }
        }
        .navigationTitle(summary.activityName)
    }

    @ViewBuilder
    private var extractionStatusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            switch status {
            case .notExtracted:
                Text("Not extracted")
                    .foregroundStyle(.secondary)
            case .extracting:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Extracting...")
                }
            case .sending:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Sending...")
                }
            case .sent(let date):
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Sent \(date.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.subheadline)
            case .failed(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .lineLimit(2)
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var extractButton: some View {
        switch status {
        case .extracting, .sending:
            EmptyView()
        case .sent:
            Button("Re-extract & Send") {
                Task {
                    await workoutManager.extractAndSend(workoutID: summary.id)
                }
            }
        case .notExtracted, .failed:
            Button("Extract & Send") {
                Task {
                    await workoutManager.extractAndSend(workoutID: summary.id)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.2f km", km)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m \(secs)s"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    private func formatPace(duration: TimeInterval, distance: Double) -> String {
        guard distance > 0 else { return "--" }
        let paceSecondsPerKm = duration / (distance / 1000)
        let minutes = Int(paceSecondsPerKm) / 60
        let seconds = Int(paceSecondsPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds)) /km"
    }
}
