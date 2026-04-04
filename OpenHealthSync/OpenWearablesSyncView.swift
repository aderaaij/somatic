import SwiftUI

/// Standalone Open Wearables sync UI, accessible from Settings when OW is enabled.
struct OpenWearablesSyncView: View {
    @ObservedObject var health: HealthManager
    @ObservedObject var workoutManager: WorkoutManager

    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("userId") private var userId: String = ""

    @State private var showingLogs = false
    @State private var showingConfig = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                lastSyncInfo
                syncProgressSection
                tierToggles
                syncButton
            }
            .padding()
        }
        .navigationTitle("Open Wearables Sync")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingLogs = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    Button {
                        showingConfig = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingLogs) {
            logsSheet
        }
        .sheet(isPresented: $showingConfig) {
            owConfigSheet
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

    private var owConfigSheet: some View {
        NavigationStack {
            OpenWearablesConfigView(
                health: health,
                onDismiss: { showingConfig = false }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingConfig = false
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

// MARK: - Open Wearables Config (sub-view for OW server settings)

struct OpenWearablesConfigView: View {
    @ObservedObject var health: HealthManager
    let onDismiss: () -> Void

    @State private var owURL = ""
    @State private var owUserId = ""
    @State private var owAPIKey = ""
    @State private var apiKeyVisible = false

    @AppStorage("serverURL") private var storedServerURL: String = ""
    @AppStorage("userId") private var storedUserId: String = ""

    var body: some View {
        Form {
            Section("Open Wearables Server") {
                TextField("Server URL", text: $owURL)
                    .keyboardType(.URL)
                    .textContentType(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("User ID", text: $owUserId)
                    .textContentType(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    if apiKeyVisible {
                        TextField("API Key", text: $owAPIKey)
                            .textContentType(.none)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("API Key", text: $owAPIKey)
                            .textContentType(.none)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        apiKeyVisible.toggle()
                    } label: {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("Save & Reconnect") {
                    let url = owURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let user = owUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = owAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    storedServerURL = url
                    storedUserId = user
                    health.signOutAndReset()
                    health.setup(host: url, userId: user, apiKey: key)
                    onDismiss()
                }
                .disabled(owURL.isEmpty || owUserId.isEmpty || owAPIKey.isEmpty)
            }

            Section {
                Button("Disconnect Open Wearables", role: .destructive) {
                    health.signOutAndReset()
                    storedServerURL = ""
                    storedUserId = ""
                    onDismiss()
                }
            }
        }
        .navigationTitle("Open Wearables")
        .onAppear {
            owURL = storedServerURL
            owUserId = storedUserId
        }
    }
}
