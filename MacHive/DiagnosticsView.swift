import SwiftUI
import Foundation
import Network

struct DiagnosticsView: View {
    @ObservedObject var exo: ExoManager
    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false
    @State private var testingExo = false
    @State private var testResult: String? = nil

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

            Button("Run Checks Again") {
                runChecks()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(isRunning)

            Button("Test exo") {
                testExo()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(testingExo)

            Button("Copy Results") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let text = results.map { "\($0.passed ? "✅" : "❌") \($0.title)\($0.detail.map { ": \($0)" } ?? "")" }.joined(separator: "\n")
                if let testResult = testResult {
                    pasteboard.setString(text + "\n\nTest exo: \(testResult)", forType: .string)
                } else {
                    pasteboard.setString(text, forType: .string)
                }
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

        let exoInstalled = ExoManager.exoIsInstalled
        let exoRunning = exo.isRunning

        results = [
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
                detail: exoRunning ? "Yes" : "Not started"
            ),
            DiagnosticResult.check(
                title: "Network available",
                passed: Self.isNetworkReachable,
                detail: Self.isNetworkReachable ? nil : "No active network connection"
            ),
            DiagnosticResult.check(
                title: "Firewall status",
                passed: !Self.isFirewallEnabled,
                detail: Self.isFirewallEnabled ? "macOS firewall may block local discovery" : "Firewall is off"
            ),
            DiagnosticResult.check(
                title: "Local network permission",
                passed: true,
                detail: "If macOS asked, click Allow"
            )
        ]
        isRunning = false
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

    private static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private static var isNetworkReachable: Bool {
        let monitor = NWPathMonitor()
        var available = false
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            available = path.status == .satisfied
            semaphore.signal()
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()
        return available
    }

    private static var isFirewallEnabled: Bool {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "/Library/Preferences/com.apple.alf", "globalstate"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.availableData
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return text != "0"
            }
        } catch {
            return false
        }
        return false
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
    DiagnosticsView(exo: ExoManager())
}
