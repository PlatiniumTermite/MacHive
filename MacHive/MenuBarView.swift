import SwiftUI

struct MenuBarView: View {
    @StateObject private var state = ClusterState()
    @StateObject private var discovery = PeerDiscovery()
    @StateObject private var exo = ExoManager()
    @State private var showingStopConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            peerList
            Divider()
            controls
            Divider()
            statusFooter
            Divider()
            settingsSection
        }
        .frame(width: 320)
        .onAppear {
            discovery.start()
            updatePeers()
        }
        .onChange(of: discovery.peers) { _ in
            updatePeers()
        }
        .onChange(of: exo.isRunning) { running in
            if running {
                state.status = .running
            } else if state.status == .running || state.status == .starting || state.status == .ready {
                state.status = .notRunning
            }
        }
        .onChange(of: exo.lastError) { error in
            if let error = error {
                state.status = .error(error)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MacHive")
                .font(.title3)
                .fontWeight(.bold)

            HStack(spacing: 6) {
                Circle()
                    .fill(state.status == .running || state.status == .ready ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("\(state.onlinePeerCount) Mac\(state.onlinePeerCount == 1 ? "" : "s") found — \(state.combinedRAMGB) GB combined")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(state.peers) { peer in
                HStack(spacing: 8) {
                    Circle()
                        .fill(peer.isOnline ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.name)
                            .font(.body)
                        Text("\(peer.chip) · \(peer.ramGB) GB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Model:", selection: $state.selectedModel) {
                ForEach(ExoModel.allCases) { model in
                    Text(model.rawValue)
                        .tag(model)
                        .disabled(!state.canRunModel(model))
                }
            }
            .pickerStyle(.menu)
            .disabled(exo.isRunning)

            if !state.selectedModelFits {
                Text("Needs \(state.selectedModel.requiredRAMGB)GB, you have \(state.combinedRAMGB)GB combined")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("This model requires more combined RAM than is currently available from online Macs.")
            }

            if exo.isRunning {
                Button("Open Chat") {
                    exo.openChat()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("Stop Cluster") {
                    showingStopConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .alert("Stop the cluster?", isPresented: $showingStopConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Stop", role: .destructive) {
                        exo.stop()
                        state.status = .notRunning
                    }
                } message: {
                    Text("This will stop the exo process on this Mac.")
                }
            } else {
                Button("Start AI Cluster") {
                    state.status = .starting
                    exo.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!state.selectedModelFits)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var statusFooter: some View {
        HStack {
            Text("Status:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(state.status.display)
                .font(.callout)
                .foregroundStyle(statusColor)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch state.status {
        case .notRunning: return .secondary
        case .starting: return .orange
        case .ready, .running: return .green
        case .error: return .red
        }
    }

    private var settingsSection: some View {
        HStack {
            Toggle("Launch MacHive at login", isOn: $state.launchAtLogin)
                .font(.callout)
                .onChange(of: state.launchAtLogin) { value in
                    LaunchAtLoginManager.setEnabled(value)
                }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .onAppear {
            state.launchAtLogin = LaunchAtLoginManager.isEnabled()
        }
    }

    private func updatePeers() {
        state.peers = discovery.peers
        if !state.peers.contains(where: { $0.id == state.localPeer.id }) {
            state.peers.append(state.localPeer)
            state.peers.sort { $0.name < $1.name }
        }
    }
}

#Preview {
    MenuBarView()
}
