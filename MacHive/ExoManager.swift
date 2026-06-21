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
        isRunning = true

        guard ExoManager.exoIsInstalled else {
            lastError = "exo is not installed. Run setup first."
            isRunning = false
            return
        }

        let task = Process()
        task.launchPath = "/bin/zsh"

        let command = "cd \"\(exoDirectory)\" && uv run exo --namespace machive"
        task.arguments = ["-c", command]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
                    self.lastError = "exo exited unexpectedly (code \(task.terminationStatus))."
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

    private func appendLog(_ line: String) {
        recentLogs.append(line)
        if recentLogs.count > maxLogLines {
            recentLogs.removeFirst(recentLogs.count - maxLogLines)
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

private extension ExoManager {
    static var exoIsInstalled: Bool {
        let fm = FileManager.default
        let base = "\(NSHomeDirectory())/Library/Application Support/MacHive/exo"
        let mainPath = "\(base)/src/exo/main.py"
        let pyprojectPath = "\(base)/pyproject.toml"
        return fm.fileExists(atPath: mainPath) && fm.fileExists(atPath: pyprojectPath)
    }
}
