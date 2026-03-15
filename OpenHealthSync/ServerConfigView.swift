import SwiftUI

struct ServerConfigView: View {
    enum Mode {
        case onboarding
        case settings
    }

    let mode: Mode
    let onSave: (_ serverURL: String, _ userId: String, _ apiKey: String) -> Void
    var onSignOut: (() -> Void)? = nil

    @State private var serverURL = ""
    @State private var userId = ""
    @State private var apiKey = ""
    @State private var apiKeyVisible = false

    @AppStorage("serverURL") private var storedServerURL: String = ""
    @AppStorage("userId") private var storedUserId: String = ""

    var body: some View {
        Form {
            Section("Server Configuration") {
                TextField("Server URL", text: $serverURL)
                    .keyboardType(.URL)
                    .textContentType(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("User ID", text: $userId)
                    .textContentType(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    if apiKeyVisible {
                        TextField("API Key", text: $apiKey)
                            .textContentType(.none)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("API Key", text: $apiKey)
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
                Button(mode == .onboarding ? "Connect" : "Save & Reconnect") {
                    onSave(
                        serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        userId.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .disabled(serverURL.isEmpty || userId.isEmpty || apiKey.isEmpty)
            }

            if mode == .settings, let onSignOut {
                Section {
                    Button("Sign Out & Reset", role: .destructive) {
                        onSignOut()
                    }
                }
            }
        }
        .navigationTitle(mode == .onboarding ? "Welcome to Somatic" : "Settings")
        .onAppear {
            if mode == .settings {
                serverURL = storedServerURL
                userId = storedUserId
            }
        }
    }
}

#Preview("Onboarding") {
    NavigationStack {
        ServerConfigView(mode: .onboarding) { _, _, _ in }
    }
}

#Preview("Settings") {
    NavigationStack {
        ServerConfigView(mode: .settings, onSave: { _, _, _ in }, onSignOut: {})
    }
}
