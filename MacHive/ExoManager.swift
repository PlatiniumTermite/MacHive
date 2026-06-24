import Foundation
import AppKit

@MainActor
final class ExoManager: ObservableObject {
    @Published var isRunning: Bool = false {
        didSet {
            UserDefaults.standard.set(isRunning, forKey: "MacHiveClusterRunning")
            NotificationCenter.default.post(name: NSNotification.Name("MacHiveStatusChanged"), object: nil)
        }
    }
    @Published var lastError: String? = nil
    @Published var exoPeerCount: Int = 0
    @Published var exoPeerStatus: String = "Not started"

    private var process: Process?
    private var statusTimer: Timer?
    private var restartAttempts: Int = 0
    private let maxRestartAttempts: Int = 3
    private var recentLogs: [String] = []
    private let maxLogLines: Int = 100
    private let exoDirectory = "\(NSHomeDirectory())/Library/Application Support/MacHive/exo"

    var dashboardURL: URL {
        URL(string: "http://localhost:52415")!
    }

    func start() {
        guard !isRunning else { return }
        lastError = nil
        
        // Pre-flight network checks
        let networkIssues = NetworkHelper.checkNetworkRequirements()
        if !networkIssues.isEmpty {
            NSLog("MacHive: Network warnings: \(networkIssues.joined(separator: "; "))")
            // Don't block startup, just log warnings
        }
        
        isRunning = true

        guard ExoManager.exoIsInstalled else {
            lastError = "exo is not installed. Run setup first."
            isRunning = false
            return
        }

        // Pre-sync exo dependencies in the background to avoid runtime failures
        Task {
            let syncTask = Process()
            syncTask.launchPath = "/bin/zsh"
            syncTask.currentDirectoryPath = exoDirectory
            syncTask.arguments = ["-c", "uv sync"]
            var syncEnv = ProcessInfo.processInfo.environment
            syncEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            syncEnv["HOME"] = NSHomeDirectory()
            syncTask.environment = syncEnv
            do {
                try syncTask.run()
            } catch {
                NSLog("MacHive: uv sync failed to start: \(error.localizedDescription)")
            }
        }

        let task = Process()
        task.launchPath = "/bin/zsh"
        task.currentDirectoryPath = exoDirectory

        let command = "uv run exo --namespace machive"
        task.arguments = ["-c", command]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["RUST_LOG"] = "info,libp2p=debug,exo=debug"
        env["LIBP2P_FORCE_PNET"] = "0"
        env["HOME"] = NSHomeDirectory()
        task.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                NSLog("[exo stdout] \(text)")
                Task { @MainActor [weak self] in
                    self?.appendLog("[stdout] \(text)")
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                NSLog("[exo stderr] \(text)")
                Task { @MainActor [weak self] in
                    self?.appendLog("[stderr] \(text)")
                    if text.lowercased().contains("error") {
                        self?.lastError = text
                    }
                }
            }
        }

        task.terminationHandler = { [weak self] task in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.process = nil
                self.isRunning = false
                if task.terminationStatus != 0, self.lastError == nil {
                    let recent = self.recentLogs.suffix(5).joined(separator: "\n")
                    self.lastError = "exo exited unexpectedly (code \(task.terminationStatus)).\n\nRecent logs:\n\(recent)"
                }
                if self.restartAttempts < self.maxRestartAttempts {
                    self.restartAttempts += 1
                    let delay = Double(self.restartAttempts) * 2.0
                    self.lastError = (self.lastError ?? "") + " Retrying in \(Int(delay))s... (\(self.restartAttempts)/\(self.maxRestartAttempts))"
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.start()
                        }
                    }
                }
            }
        }

        do {
            try task.run()
            process = task
            restartAttempts = 0
            startPolling()
        } catch {
            lastError = "Failed to start exo: \(error.localizedDescription)"
            isRunning = false
            process = nil
        }
    }

    func stop() {
        restartAttempts = maxRestartAttempts
        statusTimer?.invalidate()
        statusTimer = nil
        process?.terminate()
        if let process = process, process.isRunning {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                if process.isRunning {
                    process.kill()
                }
                Task { @MainActor [weak self] in
                    self?.process = nil
                    self?.isRunning = false
                }
            }
        } else {
            self.process = nil
            self.isRunning = false
        }
    }

    func openChat() {
        NSWorkspace.shared.open(dashboardURL)
    }

    func copyLogsToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = recentLogs.joined(separator: "\n")
        pasteboard.setString(text, forType: .string)
    }

    func testExoInstallation() async -> String {
        let result = await runShell("cd \"\(exoDirectory)\" && uv run exo --help", environment: [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ], timeout: 30, onOutput: nil)
        if result.terminationStatus == 0 {
            return "exo responded successfully."
        } else {
            let output = (result.stdout + "\n" + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return "exo test failed (code \(result.terminationStatus)): \(output.isEmpty ? "No output" : output)"
        }
    }

    private func appendLog(_ line: String) {
        recentLogs.append(line)
        if recentLogs.count > maxLogLines {
            recentLogs.removeFirst(recentLogs.count - maxLogLines)
        }

        // Parse exo logs for peer connection status
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if line.contains("Connected to peer") || line.contains("connected to peer") || line.contains("peer") && line.contains("connected") {
                self.exoPeerStatus = "Peers connected"
            } else if line.contains("Waiting for peer") || line.contains("Listening") || line.contains("Node ID") {
                self.exoPeerStatus = "Waiting for peers..."
            } else if line.contains("Partition") {
                self.exoPeerStatus = "Model distributed across peers"
            }
            // Count connected peers by counting "Connected to peer" occurrences
            let connectedLines = self.recentLogs.filter { $0.contains("Connected to peer") || $0.contains("connected to peer") }
            self.exoPeerCount = connectedLines.count
        }
    }

    private func startPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    private func checkStatus() {
        guard let url = URL(string: "http://localhost:52415") else { return }
        let request = URLRequest(url: url, timeoutInterval: 2.0)
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            Task { @MainActor [weak self] in
                if response == nil {
                    if (self?.process?.isRunning ?? false) {
                        self?.isRunning = true
                    } else {
                        self?.isRunning = false
                    }
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.isRunning = true
                    self?.lastError = nil
                }
            }
        }
        task.resume()
    }
}

private extension Process {
    func kill() {
        let killTask = Process()
        killTask.launchPath = "/bin/kill"
        killTask.arguments = ["-9", "\(processIdentifier)"]
        try? killTask.run()
    }
}

extension ExoManager {
    static var exoIsInstalled: Bool {
        let fm = FileManager.default
        let base = "\(NSHomeDirectory())/Library/Application Support/MacHive/exo"
        let mainPath = "\(base)/src/exo/main.py"
        let pyprojectPath = "\(base)/pyproject.toml"
        return fm.fileExists(atPath: mainPath) && fm.fileExists(atPath: pyprojectPath)
    }
}
