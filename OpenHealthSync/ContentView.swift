import SwiftUI

struct SyncTabView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var workoutManager: WorkoutManager

    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("userId") private var userId: String = ""

    @State private var showingSettings = false
    @State private var showingLogs = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                lastSyncInfo
                syncProgressSection
                workoutTimelineLink
                tierToggles
                syncButton
            }
            .padding()
        }
        .navigationTitle("Somatic")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingLogs = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showingLogs) {
            logsSheet
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(health.status)
                .font(.headline)
            Spacer()
            if health.syncProgress.isSyncing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch health.status {
        case "Connected": .green
        case "Permission denied": .red
        case _ where health.status.contains("Auth error"): .red
        case _ where health.status.contains("expired"): .orange
        case "Not connected": .gray
        default: .yellow
        }
    }

    // MARK: - Last Sync Info

    @ViewBuilder
    private var lastSyncInfo: some View {
        if let lastDate = health.lastSyncDate {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("Last synced")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lastDate, style: .relative) ago")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    // MARK: - Sync Progress

    @ViewBuilder
    private var syncProgressSection: some View {
        let progress = health.syncProgress
        if !progress.types.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Summary row
                HStack {
                    if progress.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else if progress.completedCount == progress.totalCount {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text(progress.statusSummary)
                        .font(.subheadline)
                    Spacer()
                    if progress.totalSent > 0 {
                        Text("\(progress.totalSent) samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: progress.fractionComplete)
                    .tint(progress.isSyncing ? .blue : .green)

                // Collapsible type details
                DisclosureGroup("Details (\(progress.completedCount)/\(progress.totalCount))") {
                    VStack(spacing: 6) {
                        ForEach(progress.types) { typeInfo in
                            HStack(spacing: 8) {
                                typeStatusIcon(typeInfo.status)
                                    .frame(width: 16)
                                Text(typeInfo.displayName)
                                    .font(.caption)
                                Spacer()
                                typeStatusLabel(typeInfo)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func typeStatusIcon(_ status: TypeSyncStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption2)
        case .querying:
            ProgressView()
                .controlSize(.mini)
        case .syncing:
            ProgressView()
                .controlSize(.mini)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .skipped:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }

    private func typeStatusLabel(_ info: TypeSyncInfo) -> Text {
        switch info.status {
        case .pending:
            Text("Waiting")
        case .querying:
            Text("Querying...")
        case .syncing(let samples):
            Text("\(samples) samples")
        case .complete:
            if info.sampleCount > 0 {
                Text("\(info.sampleCount) samples")
            } else {
                Text("Done")
            }
        case .skipped:
            Text("Up to date")
        }
    }

    // MARK: - Workout Timeline Link

    private var workoutTimelineLink: some View {
        NavigationLink {
            WorkoutListView(workoutManager: workoutManager)
        } label: {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                Text("Workouts")
                    .font(.subheadline)
                Spacer()
                if workoutManager.workouts.count > 0 {
                    Text("\(workoutManager.workouts.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tier Toggles

    private var tierToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Tiers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(HealthDataTier.allCases) { tier in
                Toggle(isOn: Binding(
                    get: { health.enabledTiers.contains(tier) },
                    set: { enabled in
                        if enabled {
                            health.enabledTiers.insert(tier)
                        } else if tier != .core {
                            health.enabledTiers.remove(tier)
                        }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(tier.displayName)
                            .font(.subheadline)
                        Text(tier.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(tier == .core)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Sync Button

    private var syncButton: some View {
        Group {
            if health.syncProgress.isSyncing {
                Button("Stop Sync", role: .destructive) {
                    health.stopSync()
                }
                .buttonStyle(.bordered)
            } else {
                VStack(spacing: 4) {
                    Button("Sync Now") {
                        health.syncNow()
                    }
                    .buttonStyle(.borderedProminent)

                    if health.lastSyncDate == nil {
                        Text("First sync may take a few minutes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sheets

    private var settingsSheet: some View {
        NavigationStack {
            ServerConfigView(
                mode: .settings,
                onSave: { url, user, key in
                    serverURL = url
                    userId = user
                    health.signOutAndReset()
                    health.setup(host: url, userId: user, apiKey: key)
                    showingSettings = false
                },
                onSignOut: {
                    health.signOutAndReset()
                    showingSettings = false
                    serverURL = ""
                    userId = ""
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSettings = false
                    }
                }
            }
        }
    }

    private var logsSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(health.logs, id: \.self) { log in
                        Text(log)
                            .font(.caption)
                            .fontDesign(.monospaced)
                    }
                }
                .padding()
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingLogs = false
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SyncTabView(
            health: HealthManager(),
            workoutManager: WorkoutManager()
        )
    }
}
