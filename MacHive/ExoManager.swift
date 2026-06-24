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
    @Published var isPreparing: Bool = false
    @Published var lastError: String? = nil
    @Published var exoPeerCount: Int = 0
    @Published var exoPeerStatus: String = "Not started"
    @Published var statusText: String = "Not started"
    @Published private(set) var recentLogs: [String] = []
    private var startWatchdogTimer: Timer?

    private var process: Process?
    private var statusTimer: Timer?
    private var restartAttempts: Int = 0
    private let maxRestartAttempts: Int = 3
    private let maxLogLines: Int = 100
    private let exoDirectory = "\(NSHomeDirectory())/Library/Application Support/MacHive/exo"

    var dashboardURL: URL {
        URL(string: "http://localhost:52415")!
    }

    func start(namespace: String = "machive") {
        guard !isRunning && !isPreparing else { return }
        lastError = nil

        // Pre-flight network checks
        let networkIssues = NetworkHelper.checkNetworkRequirements()
        if !networkIssues.isEmpty {
            NSLog("MacHive: Network warnings: \(networkIssues.joined(separator: "; "))")
        }

        guard ExoManager.exoIsInstalled else {
            lastError = "exo is not installed. Run setup first."
            return
        }

        let safeNamespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "machive" : namespace

        isPreparing = true
        statusText = "Starting exo..."
        startWatchdogTimer?.invalidate()
        startWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.statusText != "Cluster started" && self.statusText != "Cluster stopped" {
                    self.lastError = "Cluster is taking too long to start. Try clicking Stop, then Clear uv Locks in Diagnostics, then Start again."
                    self.statusText = "Cluster start timed out"
                }
            }
        }

        Task {
            // Step 1: Kill any stuck uv processes, clear stale locks, and remove exo pidfile
            await clearUVLocksInternal()
            await removeExoPidfile()

            // Step 2: Start exo (uv run will sync automatically if needed)
            await MainActor.run { [weak self] in
                self?.statusText = "Starting exo..."
            }
            await launchExo(namespace: safeNamespace)
        }
    }

    func clearUVLocks() async -> String {
        let result = await runShell("pkill -f 'uv run' 2>/dev/null; pkill -f 'uv sync' 2>/dev/null; rm -f /var/folders/*/uv-*.lock 2>/dev/null; rm -f \"\(exoDirectory)/.venv/.lock\" 2>/dev/null; sleep 1", environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ], timeout: 10, onOutput: nil)
        if result.terminationStatus == 0 {
            return "Stale uv locks cleared. Stop and restart the cluster."
        } else {
            return "Lock clear finished (exit code \(result.terminationStatus))."
        }
    }

    private func removeExoPidfile() async {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/exo")
        let pidFile = cacheDir.appendingPathComponent("exo.pid")
        if FileManager.default.fileExists(atPath: pidFile.path) {
            if let pidString = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = Int(pidString.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
                _ = await runShell("kill -9 \(pid) 2>/dev/null; sleep 1", environment: [
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
                ], timeout: 5, onOutput: nil)
            }
            try? FileManager.default.removeItem(at: pidFile)
        }
    }

    private func clearUVLocksInternal() async {
        let _ = await runShell("pkill -f 'uv run' 2>/dev/null; pkill -f 'uv sync' 2>/dev/null; rm -f /var/folders/*/uv-*.lock 2>/dev/null; rm -f \"\(exoDirectory)/.venv/.lock\" 2>/dev/null; sleep 1", environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ], timeout: 10, onOutput: nil)
    }

    private func launchExo(namespace: String) async {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.currentDirectoryPath = exoDirectory

        let command = "uv run exo --namespace \(namespace)"
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
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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

            // Verify the server actually responds before claiming it is running
            let serverReady = await waitForServer(timeout: 30)
            if serverReady {
                isRunning = true
                isPreparing = false
                statusText = "Cluster started"
            } else {
                lastError = "exo process started but server is not responding on localhost:52415"
                isRunning = false
                isPreparing = false
                process?.terminate()
                process?.kill()
                process = nil
                statusText = "Server failed to respond"
            }
            startWatchdogTimer?.invalidate()
            startWatchdogTimer = nil
        } catch {
            lastError = "Failed to start exo: \(error.localizedDescription)"
            isRunning = false
            isPreparing = false
            process = nil
            statusText = "Cluster failed to start"
            startWatchdogTimer?.invalidate()
            startWatchdogTimer = nil
        }
    }

    private func waitForServer(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let url = URL(string: "http://localhost:52415")!
        let request = URLRequest(url: url, timeoutInterval: 3.0)

        while Date() < deadline {
            let result = await withCheckedContinuation { continuation in
                URLSession.shared.dataTask(with: request) { _, response, _ in
                    continuation.resume(returning: (response as? HTTPURLResponse)?.statusCode == 200)
                }.resume()
            }
            if result { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    func stop() {
        restartAttempts = maxRestartAttempts
        statusTimer?.invalidate()
        statusTimer = nil
        startWatchdogTimer?.invalidate()
        startWatchdogTimer = nil
        statusText = "Stopping cluster..."
        isRunning = false
        isPreparing = false

        // Force kill the main process and all child processes
        if let process = process {
            process.terminate()
            if process.isRunning {
                process.kill()
            }
        }
        process = nil

        // Kill any leftover exo or uv processes that may hold locks, and remove the pidfile
        Task {
            await removeExoPidfile()
            let _ = await runShell("pkill -f 'uv run exo' 2>/dev/null; pkill -f 'uv sync' 2>/dev/null; pkill -f 'exo' 2>/dev/null; rm -f /var/folders/*/uv-*.lock 2>/dev/null; rm -f \"\(exoDirectory)/.venv/.lock\" 2>/dev/null; sleep 1", environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": NSHomeDirectory()
            ], timeout: 10, onOutput: nil)
            await MainActor.run { [weak self] in
                self?.statusText = "Cluster stopped"
            }
        }
    }

    func openChat() {
        guard let url = URL(string: "http://localhost:52415") else { return }
        let request = URLRequest(url: url, timeoutInterval: 3.0)
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            Task { @MainActor [weak self] in
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    NSWorkspace.shared.open(self?.dashboardURL ?? url)
                } else {
                    self?.lastError = "Chat server is not responding at localhost:52415. exo may still be starting or the dashboard build failed. Click Copy Logs and wait 30 seconds, then try again."
                }
            }
        }
        task.resume()
    }

    func copyLogsToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = recentLogs.joined(separator: "\n")
        pasteboard.setString(text, forType: .string)
    }

    func rebuildDashboard() async -> String {
        let result = await runShell("cd \"\(exoDirectory)/dashboard\" && npm install && npm run build", environment: [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ], timeout: 300, onOutput: nil)
        if result.terminationStatus == 0 {
            return "Dashboard rebuilt successfully. Stop and restart the cluster."
        } else {
            let output = (result.stdout + "\n" + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return "Dashboard build failed (code \(result.terminationStatus)): \(output.isEmpty ? "No output" : output)"
        }
    }

    func testExoInstallation() async -> String {
        let result = await runShell("cd \"\(exoDirectory)\" && uv run exo --help", environment: [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ], timeout: 10, onOutput: nil)
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
