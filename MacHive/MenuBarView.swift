import SwiftUI

@MainActor
struct MenuBarView: View {
    @StateObject private var state = ClusterState()
    @ObservedObject var discovery: PeerDiscovery
    @ObservedObject var exo: ExoManager
    @State private var showingStopConfirmation = false
    @State private var showingDiagnostics = false
    @State private var showingWelcome = false
    @State private var manualPeerIP: String = ""

    init(discovery: PeerDiscovery, exo: ExoManager) {
        self.discovery = discovery
        self.exo = exo
    }

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
            updatePeers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !isInApplications || isFirewallOn {
                    showingWelcome = true
                }
            }
            if state.autoStartCluster && !exo.isRunning && !exo.isPreparing && state.selectedModelFits {
                state.status = .starting
                exo.start(namespace: state.namespace)
            }
        }
        .onChange(of: discovery.peers) { _ in
            updatePeers()
        }
        .onChange(of: exo.isRunning) { running in
            if running {
                state.status = .running
                discovery.forceDiscovery()
            } else if state.status == .running || state.status == .starting || state.status == .ready {
                state.status = .notRunning
            }
        }
        .onChange(of: exo.lastError) { error in
            if let error = error {
                state.status = .error(error)
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(exo: exo, namespace: state.namespace)
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeSetupSheet(isPresented: $showingWelcome)
        }
    }

    private var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private var isFirewallOn: Bool {
        let result = Process()
        result.launchPath = "/usr/bin/defaults"
        result.arguments = ["read", "/Library/Preferences/com.apple.alf", "globalstate"]
        let pipe = Pipe()
        result.standardOutput = pipe
        try? result.run()
        result.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1"
        return text != "0"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hexagon.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacHive")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.clusterReady ? Color.green : (state.status == .running || state.status == .ready ? Color.orange : (exo.isPreparing ? Color.yellow : Color.gray)))
                        .frame(width: 8, height: 8)
                    Text("\(state.onlinePeerCount) Mac\(state.onlinePeerCount == 1 ? "" : "s") · \(state.combinedRAMGB) GB")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if state.clusterReady {
                        Text("Ready")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    } else if exo.isPreparing {
                        Text("Preparing")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else if state.status == .running || state.status == .ready {
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text(exo.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = discovery.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How to combine two Macs:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Connect both Macs to the same WiFi\n2. Set the same namespace in Settings → Advanced\n3. Click Start AI Cluster on both Macs\n4. Wait for green status dots, then click Open Chat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 2)

            if state.peers.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    if discovery.isBrowsing {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Discovery active: Bonjour + UDP broadcast + UDP multicast")
                                .font(.caption)
                            Text("Auto-scanning every 5 seconds for other Macs with MacHive...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("No other Macs found. Make sure other Macs have MacHive running on the same WiFi and namespace.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 6)
            } else {
                Text("Macs in this cluster")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                ForEach(state.peers) { peer in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(peer.isOnline ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Circle()
                                .fill(peer.isOnline ? Color.green : Color.gray)
                                .frame(width: 10, height: 10)
                                .shadow(color: peer.isOnline ? Color.green.opacity(0.5) : Color.clear, radius: 3, x: 0, y: 0)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(peer.displayInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(peer.isOnline ? "\(peer.discoveryMethod) · \(peer.ipAddress)" : "Offline")
                                .font(.caption2)
                                .foregroundStyle(peer.isOnline ? .green : .secondary)
                            if peer.namespace != state.namespace {
                                Text("⚠️ Different namespace: '\(peer.namespace)' (this Mac uses '\(state.namespace)')")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            } else {
                                Text("namespace: \(peer.namespace)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .scale))
                }
                .animation(.easeInOut(duration: 0.2), value: state.peers)
            }
        }
        .padding(.vertical, 8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker("Model:", selection: $state.selectedModel) {
                ForEach(ExoModel.allCases) { model in
                    if state.canRunModel(model) {
                        Text("\(model.rawValue) (\(model.requiredRAMGB)GB)")
                            .tag(model)
                    } else {
                        Text("\(model.rawValue) (\(model.requiredRAMGB)GB) - Not enough RAM")
                            .tag(model)
                            .disabled(true)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(exo.isRunning)

            if !state.selectedModelFits {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption)
                    Text("Needs \(state.selectedModel.requiredRAMGB)GB combined RAM · you have \(state.combinedRAMGB)GB. Start the cluster on more Macs to combine RAM.")
                        .font(.caption)
                }
                .foregroundColor(.red)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .help("This model requires more combined RAM than is currently available from online Macs.")
            }

            if state.selectedModel.requiredRAMGB >= 40 && state.selectedModelFits {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.circle")
                        .font(.caption)
                    Text("Hard model: requires \(state.selectedModel.requiredRAMGB)GB across your cluster.")
                        .font(.caption)
                }
                .foregroundColor(.orange)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
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
                        state.peers.removeAll()
                        discovery.refresh()
                    }
                } message: {
                    Text("This will stop the exo process on this Mac.")
                }
            } else if exo.isPreparing {
                Button("Preparing cluster...") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
            } else {
                Button("Start AI Cluster") {
                    state.status = .starting
                    exo.start(namespace: state.namespace)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        discovery.forceDiscovery()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: exo.isRunning)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Status")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(state.status.display)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                }
            }

            if exo.isRunning && exo.exoPeerStatus != "Not started" {
                HStack(spacing: 6) {
                    Image(systemName: exo.exoPeerCount > 0 ? "checkmark.circle.fill" : "hourglass")
                        .foregroundColor(exo.exoPeerCount > 0 ? .green : .orange)
                        .font(.caption)
                    Text(exo.exoPeerStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if case .error(let msg) = state.status {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch MacHive at login", isOn: $state.launchAtLogin)
                    .font(.callout)
                    .onChange(of: state.launchAtLogin) { value in
                        LaunchAtLoginManager.setEnabled(value)
                    }

                Toggle("Auto-start cluster on launch", isOn: $state.autoStartCluster)
                    .font(.callout)

                Toggle("Show exo logs", isOn: $state.showExoLogs)
                    .font(.callout)
            }

            if state.showExoLogs && !exo.recentLogs.isEmpty {
                ScrollView {
                    Text(exo.recentLogs.suffix(20).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                }
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 100)
                .padding(6)
                .background(Color.black.opacity(0.15))
                .cornerRadius(8)
            }

            Button("Advanced Settings") {
                state.showAdvancedSettings.toggle()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if state.showAdvancedSettings {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cluster namespace:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("machive", text: $state.namespace)
                        .font(.callout)
                        .textFieldStyle(.roundedBorder)
                        .disabled(exo.isRunning)
                    Text("All Macs must use the same namespace.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            HStack(spacing: 8) {
                TextField("192.168.1.x", text: $manualPeerIP)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                Button("Add Peer by IP") {
                    if !manualPeerIP.isEmpty {
                        discovery.addPeerByIP(manualPeerIP, name: "Manual Peer \(manualPeerIP)")
                        manualPeerIP = ""
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manualPeerIP.isEmpty)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button("Refresh Peers") {
                    discovery.refresh()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Boost Discovery") {
                    discovery.forceDiscovery()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Send 5 rapid network beacons to find other Macs immediately")

                Button("Scan Network") {
                    discovery.scanLocalSubnet()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Ping every IP on your WiFi subnet to find hidden Macs")

                Button("Diagnostics") {
                    showingDiagnostics = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Copy Logs") {
                    exo.copyLogsToPasteboard()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
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
    @MainActor
    struct PreviewWrapper: View {
        var body: some View {
            MenuBarView(discovery: PeerDiscovery(), exo: ExoManager())
        }
    }
    return PreviewWrapper()
}
