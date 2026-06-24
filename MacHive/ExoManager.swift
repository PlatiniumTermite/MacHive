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
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures: Int = 3
    private var stoppingManually: Bool = false
    private let maxLogLines: Int = 100
    private let exoDirectory = "\(NSHomeDirectory())/Library/Application Support/MacHive/exo"

    var dashboardURL: URL {
        URL(string: "http://localhost:52415")!
    }

    func start(namespace: String = "machive") {
        guard !isRunning && !isPreparing else { return }
        lastError = nil
        consecutiveFailures = 0
        restartAttempts = 0

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
                if self.statusText != "Cluster started" && self.statusText != "Cluster stopped" && self.statusText != "Still starting..." && self.statusText != "Dashboard ready" {
                    self.lastError = "Cluster is taking too long to start. Try clicking Stop, then Clear uv Locks in Diagnostics, then Start again."
                    self.statusText = "Cluster start timed out"
                }
            }
        }

        Task {
            // Step 1: Kill any stuck uv processes, clear stale locks, remove exo pidfile, and free exo ports
            await clearUVLocksInternal()
            await removeExoPidfile()
            await killPortListeners()

            // Step 2: Verify ports are actually free before launching
            let portsFree = await checkPortsFree()
            if !portsFree {
                await MainActor.run { [weak self] in
                    self?.lastError = "Ports 52414/52415 are still in use after cleanup. Another exo process is running. Stop it manually or restart your Mac."
                    self?.statusText = "Port blocked"
                    self?.isPreparing = false
                }
                startWatchdogTimer?.invalidate()
                startWatchdogTimer = nil
                return
            }

            // Step 3: Start exo directly from the venv binary
            await MainActor.run { [weak self] in
                self?.statusText = "Starting exo..."
            }
            await launchExo(namespace: safeNamespace)
        }
    }

    func clearUVLocks() async -> String {
        let result = await runShell("pkill -f 'uv run exo' 2>/dev/null; pkill -f 'uv sync' 2>/dev/null; pkill -f 'MacHive/exo/.venv/bin/exo' 2>/dev/null; pkill -f 'MacHive/exo/.venv/bin/python' 2>/dev/null; rm -f /var/folders/*/uv-*.lock 2>/dev/null; rm -f \"\(exoDirectory)/.venv/.lock\" 2>/dev/null; sleep 1", environment: [
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

    private func killPortListeners() async {
        // exo uses port 52414 for zenoh TCP and 52415 for the HTTP dashboard
        let _ = await runShell("for port in 52414 52415; do lsof -ti tcp:$port 2>/dev/null | xargs kill -9 2>/dev/null; done; sleep 1", environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ], timeout: 10, onOutput: nil)
    }

    private func checkPortsFree() async -> Bool {
        let result = await runShell("lsof -i tcp:52414,52415 2>/dev/null | grep LISTEN | wc -l", environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ], timeout: 5, onOutput: nil)
        let count = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return count == 0
    }

    private func clearUVLocksInternal() async {
        let _ = await runShell("pkill -f 'uv run exo' 2>/dev/null; pkill -f 'uv sync' 2>/dev/null; pkill -f 'MacHive/exo/.venv/bin/exo' 2>/dev/null; pkill -f 'MacHive/exo/.venv/bin/python' 2>/dev/null; rm -f /var/folders/*/uv-*.lock 2>/dev/null; rm -f \"\(exoDirectory)/.venv/.lock\" 2>/dev/null; sleep 1", environment: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory()
        ], timeout: 10, onOutput: nil)
    }

    private func launchExo(namespace: String) async {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.currentDirectoryPath = exoDirectory

        let exoBinary = "\(exoDirectory)/.venv/bin/exo"
        let command = "\"\(exoBinary)\" --namespace \(namespace)"
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
                let wasIntentionalStop = self.stoppingManually || self.statusText == "Stopping cluster..." || self.statusText == "Cluster stopped"
                if wasIntentionalStop {
                    self.stoppingManually = false
                    self.lastError = nil
                } else if task.terminationStatus != 0, self.lastError == nil {
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
                } else {
                    self.statusText = "Cluster failed to start"
                    self.isPreparing = false
                }
            }
        }

        do {
            try task.run()
            process = task
            restartAttempts = 0
            startPolling()

            // Verify the server actually responds before claiming it is running
            // exo can take a while on first launch while it downloads models or builds the dashboard
            await MainActor.run { [weak self] in
                self?.statusText = "Waiting for exo server..."
            }
            let serverReady = await waitForServer(timeout: 60)
            if serverReady {
                isRunning = true
                isPreparing = false
                statusText = "Cluster started"
            } else {
                // exo may still be downloading model weights or building the dashboard on first launch.
                // Don't kill it automatically; let the user decide or wait for the health check.
                lastError = "exo is still starting. If this is the first launch, it may be downloading model weights. Click Stop if you want to cancel, or wait and check Test Cluster."
                statusText = "Still starting..."
                // Keep isPreparing true so the UI shows it's still working
                isPreparing = true
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

    func checkExistingExo() async {
        let url = URL(string: "http://localhost:52415")!
        let request = URLRequest(url: url, timeoutInterval: 3.0)
        let result = await withCheckedContinuation { continuation in
            URLSession.shared.dataTask(with: request) { _, response, _ in
                continuation.resume(returning: (response as? HTTPURLResponse)?.statusCode == 200)
            }.resume()
        }
        if result {
            await MainActor.run { [weak self] in
                self?.isRunning = true
                self?.isPreparing = false
                self?.statusText = "Cluster already running"
                self?.startPolling()
            }
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
        stoppingManually = true
        restartAttempts = maxRestartAttempts
        consecutiveFailures = 0
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
            await killPortListeners()
            let _ = await runShell("pkill -f 'uv run exo' 2>/dev/null; pkill -f 'uv sync' 2>/dev/null; pkill -f 'MacHive/exo/.venv/bin/exo' 2>/dev/null; pkill -f 'MacHive/exo/.venv/bin/python' 2>/dev/null; rm -f /var/folders/*/uv-*.lock 2>/dev/null; rm -f \"\(exoDirectory)/.venv/.lock\" 2>/dev/null; sleep 1", environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": NSHomeDirectory()
            ], timeout: 10, onOutput: nil)
            await MainActor.run { [weak self] in
                self?.statusText = "Cluster stopped"
            }
        }
    }

    func testCluster() {
        guard let url = URL(string: "http://localhost:52415") else { return }
        let request = URLRequest(url: url, timeoutInterval: 5.0)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                if let error = error {
                    self?.lastError = "Cluster test failed: server is not reachable. Error: \(error.localizedDescription)"
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.statusText = "Cluster test passed: server is responding"
                    self?.lastError = nil
                    NSWorkspace.shared.open(self?.dashboardURL ?? URL(string: "http://localhost:52415")!)
                } else {
                    self?.lastError = "Cluster test failed: server returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                }
            }
        }
        task.resume()
    }

    func openChat() {
        guard let url = URL(string: "http://localhost:52415") else { return }
        // Retry a few times because exo can take a moment to serve the dashboard
        Task {
            for attempt in 1...5 {
                let request = URLRequest(url: url, timeoutInterval: 3.0)
                let result = await withCheckedContinuation { continuation in
                    URLSession.shared.dataTask(with: request) { _, response, _ in
                        continuation.resume(returning: (response as? HTTPURLResponse)?.statusCode == 200)
                    }.resume()
                }
                if result {
                    _ = await MainActor.run {
                        NSWorkspace.shared.open(self.dashboardURL)
                    }
                    return
                }
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            await MainActor.run { [weak self] in
                self?.lastError = "Chat server is not responding at localhost:52415. exo may still be starting or the dashboard build failed. Click Copy Logs and wait 60 seconds, then try again."
            }
        }
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

        // Parse exo logs for peer connection status and errors
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let lowercased = line.lowercased()
            if lowercased.contains("different namespaces") || lowercased.contains("namespace") && lowercased.contains("mismatch") {
                self.lastError = "Namespace mismatch: another Mac is using a different namespace. Open Settings → Advanced on every Mac and set the exact same namespace. Default is 'machive'."
                self.statusText = "Namespace mismatch"
            }
            if lowercased.contains("address already in use") || lowercased.contains("can not create a new tcp listener") {
                self.lastError = "Port 52414 or 52415 is already in use. Another exo process is still running. Click Stop Cluster, wait 5 seconds, then click Start AI Cluster again."
                self.statusText = "Port blocked by old exo process"
                self.isRunning = false
                self.isPreparing = false
            }
            if line.contains("Connected to peer") || line.contains("connected to peer") || line.contains("peer") && line.contains("connected") {
                self.exoPeerStatus = "Peers connected"
            } else if line.contains("Waiting for peer") || line.contains("Listening") || line.contains("Node ID") {
                self.exoPeerStatus = "Waiting for peers..."
            } else if line.contains("Partition") {
                self.exoPeerStatus = "Model distributed across peers"
            }
            if line.contains("Dashboard & API Ready") || line.contains("Running on http://0.0.0.0:52415") {
                self.statusText = "Dashboard ready"
            }
            if line.contains("Downloading") || line.contains("download") && line.contains("model") {
                self.statusText = "Downloading model weights..."
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
                    self?.consecutiveFailures += 1
                    guard self?.consecutiveFailures ?? 0 >= self?.maxConsecutiveFailures ?? 3 else { return }
                    if (self?.process?.isRunning ?? false) {
                        self?.isRunning = true
                        self?.statusText = "Server not responding (process still running)"
                    } else {
                        self?.isRunning = false
                        self?.statusText = "Cluster stopped"
                    }
                    return
                }
                self?.consecutiveFailures = 0
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.isRunning = true
                    self?.lastError = nil
                    if (self?.statusText ?? "").contains("not responding") {
                        self?.statusText = "Cluster running"
                    }
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
