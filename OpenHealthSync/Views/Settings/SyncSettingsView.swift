//
//  SyncSettingsView.swift
//  OpenHealthSync
//
//  Health-metrics sync toggle and the fallback server route.
//

import SwiftUI

struct SyncSettingsView: View {
    var session: SessionStore
    let healthMetricsSyncer: HealthMetricsSyncer

    @AppStorage("healthMetricsSyncEnabled") private var healthMetricsSyncEnabled: Bool = true
    @AppStorage("trainingAPIAlternativeURL") private var alternativeURLText: String = ""

    private enum BackfillState: Equatable {
        case idle
        case running
        case done(stored: Int)
        case failed
    }

    @State private var backfillState: BackfillState = .idle

    var body: some View {
        Form {
            Section("Health Metrics") {
                Toggle("Sync health data to Training API", isOn: $healthMetricsSyncEnabled)
                    .tint(LB.green)

                if healthMetricsSyncEnabled {
                    Text("Sleep, heart rate, HRV, weight, VO2Max, steps, and more are synced daily to your training server for AI coaching context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    runBackfill()
                } label: {
                    HStack {
                        Text(backfillState == .running ? "Uploading health history…" : "Re-upload health history")
                        Spacer()
                        if backfillState == .running {
                            ProgressView()
                        }
                    }
                }
                .disabled(backfillState == .running)

                switch backfillState {
                case .done(let stored):
                    Text(stored > 0
                         ? "Done — \(stored) new sleep sample\(stored == 1 ? "" : "s") stored and daily totals rebuilt."
                         : "Done — daily totals rebuilt; the server already had every sleep sample.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed:
                    Text("Upload failed. Check the server connection and try again.")
                        .font(.caption)
                        .foregroundStyle(LB.red)
                default:
                    EmptyView()
                }
            } header: {
                Text("History")
            } footer: {
                Text("Re-reads the last 12 months from Apple Health — raw sleep samples plus daily totals like steps and energy — and uploads everything to your server, which rebuilds its records. Safe to run repeatedly.")
            }

            Section {
                TextField("Fallback URL (optional)", text: $alternativeURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Fallback Server")
            } footer: {
                Text("Second route to the same server — e.g. its LAN address when the primary URL goes through Tailscale. When the primary can't be reached, requests retry here automatically. Include the scheme, like http://192.168.1.20:8000.")
            }
        }
        .listRowBackground(LB.surface)
        .lbList()
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: alternativeURLText) { _, _ in
            // Push the new fallback route to the live clients immediately;
            // @AppStorage already persisted the text.
            Task { await session.applyAlternativeURL() }
        }
    }

    private func runBackfill() {
        backfillState = .running
        Task {
            do {
                let result = try await healthMetricsSyncer.backfillHealthHistory()
                backfillState = .done(stored: result.stored)
            } catch {
                backfillState = .failed
            }
        }
    }
}
