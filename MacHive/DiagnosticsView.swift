import SwiftUI
import Foundation
import Network

struct DiagnosticsView: View {
    @ObservedObject var exo: ExoManager
    let namespace: String
    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false
    @State private var testingExo = false
    @State private var testResult: String? = nil
    @State private var isFirewallOn = false
    @State private var rebuildingDashboard = false
    @State private var rebuildResult: String? = nil
    @State private var clearingLocks = false
    @State private var clearLocksResult: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacHive Diagnostics")
                .font(.title3)
                .fontWeight(.bold)

            Text("These checks help find common setup problems.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isRunning {
                ProgressView()
                    .padding(.vertical)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.passed ? .green : .red)
                                .font(.callout)
                                .animation(.easeInOut(duration: 0.2), value: result.passed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                if let detail = result.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    .animation(.easeInOut(duration: 0.2), value: results)
                }
            }
            .frame(minHeight: 120)

            if let testResult = testResult {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: testResult.contains("successfully") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(testResult.contains("successfully") ? .green : .orange)
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            if !Self.isInApplications {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MacHive must be in /Applications for network permissions and local discovery to work correctly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Move MacHive to /Applications") {
                        moveToApplications()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }

            if isFirewallOn {
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS firewall is ON. This blocks MacHive from discovering other Macs. Click the button below, then turn OFF the firewall.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Firewall Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.security.firewall") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            if !exo.isRunning && ExoManager.exoIsInstalled {
                Button("Start AI Cluster") {
                    exo.start(namespace: namespace)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            Button("Run Checks Again") {
                runChecks()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(isRunning)

            Button("Test exo") {
                testExo()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(testingExo)

            Button("Rebuild Dashboard") {
                rebuildDashboard()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(rebuildingDashboard)

            Button("Clear uv Locks") {
                clearUVLocks()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(clearingLocks)

            if let testResult = testResult, !testingExo {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: testResult.contains("failed") || testResult.contains("Could not") ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(testResult.contains("failed") || testResult.contains("Could not") ? .red : .green)
                    Text("Test exo: \(testResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            if let rebuildResult = rebuildResult, !rebuildingDashboard {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: rebuildResult.contains("failed") ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(rebuildResult.contains("failed") ? .red : .green)
                    Text("Dashboard: \(rebuildResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            if let clearLocksResult = clearLocksResult, !clearingLocks {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: clearLocksResult.contains("failed") ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(clearLocksResult.contains("failed") ? .red : .green)
                    Text("Locks: \(clearLocksResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            Button("Copy Results") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let text = results.map { "\($0.passed ? "✅" : "❌") \($0.title)\($0.detail.map { ": \($0)" } ?? "")" }.joined(separator: "\n")
                var full = text
                if let testResult = testResult {
                    full += "\n\nTest exo: \(testResult)"
                }
                if let rebuildResult = rebuildResult {
                    full += "\n\nDashboard: \(rebuildResult)"
                }
                if let clearLocksResult = clearLocksResult {
                    full += "\n\nLocks: \(clearLocksResult)"
                }
                pasteboard.setString(full, forType: .string)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(results.isEmpty)
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            runChecks()
        }
    }

    private func runChecks() {
        isRunning = true
        results = []

        Task {
            let exoInstalled = ExoManager.exoIsInstalled
            let exoRunning = exo.isRunning
            let networkReachable = await Self.isNetworkReachableAsync
            let firewallEnabled = await Self.isFirewallEnabledAsync

            let newResults = [
            DiagnosticResult.check(
                title: "macOS version",
                passed: ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)),
                detail: "Requires macOS 13 or later"
            ),
            DiagnosticResult.check(
                title: "MacHive in /Applications",
                passed: Self.isInApplications,
                detail: Self.isInApplications ? nil : "Move MacHive.app to /Applications"
            ),
            DiagnosticResult.check(
                title: "Apple Silicon chip",
                passed: SystemInfo.chipModel.contains("Apple") || SystemInfo.chipModel.hasPrefix("M"),
                detail: SystemInfo.chipModel
            ),
            DiagnosticResult.check(
                title: "exo installed",
                passed: exoInstalled,
                detail: exoInstalled ? nil : "Run setup or install-deps.sh"
            ),
            DiagnosticResult.check(
                title: "exo running",
                passed: exoRunning,
                detail: exoRunning ? "Yes" : "Click 'Start AI Cluster' above"
            ),
            DiagnosticResult.check(
                title: "Network available",
                passed: networkReachable,
                detail: networkReachable ? nil : "No active network connection"
            ),
            DiagnosticResult.check(
                title: "Firewall status",
                passed: !firewallEnabled,
                detail: firewallEnabled ? "macOS firewall may block local discovery" : "Firewall is off"
            ),
            DiagnosticResult.check(
                title: "Local network permission",
                passed: true,
                detail: "If macOS asked, click Allow"
            )
            ]

            await MainActor.run {
                self.results = newResults
                self.isFirewallOn = firewallEnabled
                self.isRunning = false
            }
        }
    }

    private func testExo() {
        testingExo = true
        testResult = "Running exo test..."
        Task {
            let result = await exo.testExoInstallation()
            await MainActor.run {
                testResult = result
                testingExo = false
            }
        }
    }

    private func rebuildDashboard() {
        rebuildingDashboard = true
        rebuildResult = "Rebuilding dashboard..."
        Task {
            let result = await exo.rebuildDashboard()
            await MainActor.run {
                rebuildResult = result
                rebuildingDashboard = false
            }
        }
    }

    private func clearUVLocks() {
        clearingLocks = true
        clearLocksResult = "Clearing stale uv locks..."
        Task {
            let result = await exo.clearUVLocks()
            await MainActor.run {
                clearLocksResult = result
                clearingLocks = false
            }
        }
    }

    private static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications/\(source.lastPathComponent)")
        Task {
            let result = await runShell("rm -rf \"\(destination.path)\" && cp -R \"\(source.path)\" \"\(destination.path)\" && touch \"\(destination.path)\"", environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
            ], timeout: 60, onOutput: nil)
            await MainActor.run {
                if result.terminationStatus == 0 {
                    NSWorkspace.shared.open(destination)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }
            }
        }
    }

    private static var isNetworkReachable: Bool {
        get async {
            let monitor = NWPathMonitor()
            return await withCheckedContinuation { continuation in
                monitor.pathUpdateHandler = { path in
                    continuation.resume(returning: path.status == .satisfied)
                    monitor.cancel()
                }
                monitor.start(queue: DispatchQueue.global(qos: .background))
            }
        }
    }

    private static var isNetworkReachableAsync: Bool {
        get async {
            await Self.isNetworkReachable
        }
    }

    private static var isFirewallEnabled: Bool {
        get async {
            let result = await runShell("/usr/bin/defaults read /Library/Preferences/com.apple.alf globalstate", environment: [:], timeout: 5, onOutput: nil)
            let text = (result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            return text != "0"
        }
    }

    private static var isFirewallEnabledAsync: Bool {
        get async {
            await Self.isFirewallEnabled
        }
    }
}

struct DiagnosticResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let passed: Bool
    let detail: String?

    static func check(title: String, passed: Bool, detail: String?) -> DiagnosticResult {
        DiagnosticResult(title: title, passed: passed, detail: detail)
    }
}

#Preview {
    DiagnosticsView(exo: ExoManager(), namespace: "machive")
}
