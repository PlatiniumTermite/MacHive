import SwiftUI

@MainActor
struct MenuBarView: View {
    @StateObject private var state = ClusterState()
    @ObservedObject var discovery: PeerDiscovery
    @ObservedObject var exo: ExoManager
    @State private var showingStopConfirmation = false
    @State private var showingDiagnostics = false
    @State private var showingWelcome = false
    @State private var showingFullError = false
    @State private var fullErrorMessage = ""
    @State private var manualPeerIP: String = ""
    @State private var isFixing = false

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
        }
        .onChange(of: discovery.peers) { _ in
            updatePeers()
        }
        .onChange(of: discovery.detectedForeignNamespaces) { namespaces in
            if state.autoSyncNamespace, let foreign = namespaces.first, state.namespace != foreign {
                state.namespace = foreign
            }
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
        .sheet(isPresented: $showingFullError) {
            FullErrorSheet(message: fullErrorMessage, isPresented: $showingFullError)
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
                    Text("\(state.onlinePeerCount) Mac\(state.onlinePeerCount == 1 ? "" : "s") · \(state.combinedRAMGB) GB RAM · \(state.combinedCPUThreads) cores")
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

            if !discovery.detectedForeignNamespaces.isEmpty {
                let foreign = discovery.detectedForeignNamespaces.first ?? "unknown"
                HStack(spacing: 6) {
                    Image(systemName: state.autoSyncNamespace ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.autoSyncNamespace ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.autoSyncNamespace ? "Auto-switched namespace to '\(foreign)' to match other Mac" : "Another Mac uses namespace '\(foreign)'")
                            .font(.caption)
                            .fontWeight(.semibold)
                        if !state.autoSyncNamespace {
                            Button("Switch to '\(foreign)' to match") {
                                state.namespace = foreign
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            if state.peers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if discovery.isBrowsing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Waiting for other Macs")
                            .font(.callout)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    Text("MacHive scans your WiFi every few seconds. Make sure MacHive is running on your other Macs, with the same namespace, and the firewall is off on all Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Boost discovery now") {
                        discovery.forceDiscovery()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 4)
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
                    Text("Needs \(state.selectedModel.requiredRAMGB)GB combined RAM · you have \(state.combinedRAMGB)GB. Start the cluster on more Macs to combine RAM, or switch to \(state.recommendedModel.rawValue).")
                        .font(.caption)
                }
                .foregroundColor(.red)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .help("This model requires more combined RAM than is currently available from online Macs.")
            } else if state.selectedModel != state.recommendedModel && state.onlinePeerCount >= 2 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.circle")
                        .font(.caption)
                    Text("Recommended: \(state.recommendedModel.rawValue) fits your combined RAM. Click to switch.")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
                .onTapGesture {
                    state.selectedModel = state.recommendedModel
                }
                .help("Switch to the largest model that fits your combined cluster RAM.")
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
                VStack(spacing: 8) {
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

                    Button(isFixing ? "Fixing..." : "Fix Common Issues") {
                        fixCommonIssues()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isFixing)
                    .help("Kill stuck processes, clear locks, free ports, and restart the cluster")
                }
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

            HStack(spacing: 8) {
                Text("Namespace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("'\(state.namespace)'")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if state.namespace != "machive" {
                    Button("Reset to machive") {
                        state.namespace = "machive"
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                    HStack {
                        Spacer()
                        Button("Show Full") {
                            fullErrorMessage = msg
                            showingFullError = true
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg, forType: .string)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
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

                Toggle("Auto-sync namespace with other Macs", isOn: $state.autoSyncNamespace)
                    .font(.callout)

                Toggle("Show exo logs", isOn: $state.showExoLogs)
                    .font(.callout)
            }

            if state.showExoLogs && !exo.recentLogs.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
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
                    Button("Copy Logs") {
                        exo.copyLogsToPasteboard()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
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
                    Text("All Macs must use the same namespace. Default is 'machive'. Only change if every Mac uses the same new value.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            Divider()

            Button("Quit MacHive") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
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

    private func fixCommonIssues() {
        isFixing = true
        Task {
            let _ = await exo.clearUVLocks()
            exo.stop()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                state.status = .starting
                exo.start(namespace: state.namespace)
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    discovery.forceDiscovery()
                }
                isFixing = false
            }
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
