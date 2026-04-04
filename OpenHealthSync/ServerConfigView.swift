import SwiftUI

struct ServerConfigView: View {
    enum Mode {
        case onboarding
        case settings
    }

    let mode: Mode
    var onSave: ((_ baseURL: String, _ apiKey: String) -> Void)? = nil
    var onSignOut: (() -> Void)? = nil
    var onRemoveAllWorkouts: (() async -> Void)? = nil

    @State private var showRemoveAllConfirmation = false

    // Training API fields
    @State private var trainingBaseURL = ""
    @State private var trainingAPIKey = ""
    @State private var apiKeyVisible = false

    // Persisted config
    @AppStorage("trainingAPIBaseURL") private var storedBaseURL: String = ""
    @AppStorage("trainingAPIKey") private var storedAPIKey: String = ""
    @AppStorage("preferredRunTime") private var preferredRunTime: String = PreferredRunTime.morning.rawValue
    @AppStorage("healthMetricsSyncEnabled") private var healthMetricsSyncEnabled: Bool = true
    @AppStorage("openWearablesEnabled") private var openWearablesEnabled: Bool = false
    @AppStorage("weekStartsOnMonday") private var weekStartsOnMonday: Bool = true

    // OpenWearables (only in settings)
    @AppStorage("serverURL") private var owServerURL: String = ""
    @AppStorage("userId") private var owUserId: String = ""

    var body: some View {
        Form {
            if mode == .onboarding {
                onboardingContent
            } else {
                settingsContent
            }
        }
        .navigationTitle(mode == .onboarding ? "Welcome to Somatic" : "Settings")
        .onAppear {
            if mode == .settings {
                trainingBaseURL = storedBaseURL
                trainingAPIKey = storedAPIKey
            }
        }
    }

    // MARK: - Onboarding

    private var onboardingContent: some View {
        Group {
            Section {
                Text("Connect Somatic to your training API to sync workouts, schedule training plans, and track health metrics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Training API") {
                trainingAPIFields
            }

            Section("When do you usually run?") {
                runTimePicker
            }

            Section {
                Button("Connect") {
                    let url = trainingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = trainingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    storedBaseURL = url
                    storedAPIKey = key
                    onSave?(url, key)
                }
                .disabled(trainingBaseURL.isEmpty || trainingAPIKey.isEmpty)
            }
        }
    }

    // MARK: - Settings

    private var settingsContent: some View {
        Group {
            Section("Training API") {
                trainingAPIFields

                Button("Save & Reconnect") {
                    let url = trainingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = trainingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    storedBaseURL = url
                    storedAPIKey = key
                    onSave?(url, key)
                }
                .disabled(trainingBaseURL.isEmpty || trainingAPIKey.isEmpty)
            }

            Section("Health Metrics") {
                Toggle("Sync health data to Training API", isOn: $healthMetricsSyncEnabled)

                if healthMetricsSyncEnabled {
                    Text("Sleep, heart rate, HRV, weight, VO2Max, steps, and more are synced daily to your training server for AI coaching context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Preferences") {
                runTimePicker

                Picker("Week starts on", selection: $weekStartsOnMonday) {
                    Text("Monday").tag(true)
                    Text("Sunday").tag(false)
                }
            }

            Section("Open Wearables (Advanced)") {
                Toggle("Enable Open Wearables sync", isOn: $openWearablesEnabled)

                if openWearablesEnabled {
                    Text("Syncs granular health data to a separate Open Wearables server. This is optional — health metrics are already synced to your Training API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !owServerURL.isEmpty {
                        HStack {
                            Text("Server")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(owServerURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let onRemoveAllWorkouts {
                Section("Danger Zone") {
                    Button("Remove All Scheduled Workouts", role: .destructive) {
                        showRemoveAllConfirmation = true
                    }
                    .confirmationDialog(
                        "Remove all scheduled workouts from Apple Watch?",
                        isPresented: $showRemoveAllConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Remove All", role: .destructive) {
                            Task { await onRemoveAllWorkouts() }
                        }
                    }
                }
            }

            if let onSignOut {
                Section {
                    Button("Sign Out & Reset", role: .destructive) {
                        onSignOut()
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private var trainingAPIFields: some View {
        Group {
            TextField("Server URL", text: $trainingBaseURL)
                .keyboardType(.URL)
                .textContentType(.none)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                if apiKeyVisible {
                    TextField("API Key", text: $trainingAPIKey)
                        .textContentType(.none)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("API Key", text: $trainingAPIKey)
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
    }

    private var runTimePicker: some View {
        Picker("Preferred time", selection: Binding(
            get: { PreferredRunTime(rawValue: preferredRunTime) ?? .morning },
            set: { preferredRunTime = $0.rawValue }
        )) {
            ForEach(PreferredRunTime.allCases) { time in
                Text("\(time.label) — \(time.description)").tag(time)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

#Preview("Onboarding") {
    NavigationStack {
        ServerConfigView(mode: .onboarding) { _, _ in }
    }
}

#Preview("Settings") {
    NavigationStack {
        ServerConfigView(mode: .settings, onSave: { _, _ in }, onSignOut: {})
    }
}
