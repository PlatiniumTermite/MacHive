import Foundation

enum SetupStep: String, CaseIterable {
    case homebrew = "Homebrew"
    case python = "Python 3.13"
    case uv = "uv"
    case node = "Node.js"
    case exo = "exo source"
}

enum DependencyError: Error, LocalizedError, Equatable {
    case homebrewInstallFailed(String)
    case pythonInstallFailed(String)
    case uvInstallFailed(String)
    case nodeInstallFailed(String)
    case exoCloneFailed(String)
    case exoBuildFailed(String)
    case missingTool(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .homebrewInstallFailed(let msg):
            return "Couldn't install Homebrew. \(msg)"
        case .pythonInstallFailed(let msg):
            return "Couldn't install Python. \(msg)"
        case .uvInstallFailed(let msg):
            return "Couldn't install uv (Python package manager). \(msg)"
        case .nodeInstallFailed(let msg):
            return "Couldn't install Node.js. \(msg)"
        case .exoCloneFailed(let msg):
            return "Couldn't download exo. \(msg)"
        case .exoBuildFailed(let msg):
            return "Couldn't build exo. \(msg)"
        case .missingTool(let tool):
            return "Missing required tool: \(tool)"
        case .cancelled:
            return "Installation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .homebrewInstallFailed:
            return "Open Terminal and run the install-deps.sh script included with MacHive."
        case .pythonInstallFailed, .uvInstallFailed, .nodeInstallFailed:
            return "Make sure Homebrew is installed and try again, or run install-deps.sh manually."
        case .exoCloneFailed:
            return "Check your internet connection and try again."
        case .exoBuildFailed:
            return "Node.js may be missing. Run install-deps.sh manually to fix it."
        default:
            return nil
        }
    }
}

@MainActor
final class DependencyInstaller: ObservableObject {
    @Published var progress: Double = 0
    @Published var message: String = ""
    @Published var error: DependencyError? = nil
    @Published var isRunning: Bool = false
    @Published var completedSteps: Set<SetupStep> = []
    @Published var liveOutput: String = ""

    private var currentTask: Task<Void, Never>?
    private let serialQueue = DispatchQueue(label: "com.machive.installer")

    var isComplete: Bool {
        Homebrew.isInstalled && Python.isInstalled && Exo.isInstalled
    }

    var manualInstallCommand: String {
        try? copyManualScriptToApplicationSupport()
        let scriptPath = "\(NSHomeDirectory())/Library/Application Support/MacHive/install-deps.sh"
        return "chmod +x \"\(scriptPath)\" && \"\(scriptPath)\""
    }

    func startInstallation() {
        currentTask?.cancel()
        completedSteps.removeAll()
        liveOutput = ""
        currentTask = Task { @MainActor in
            await performInstallation()
        }
    }

    func cancel() {
        currentTask?.cancel()
    }

    private func performInstallation() async {
        isRunning = true
        defer { isRunning = false }
        error = nil
        progress = 0

        let outputHandler: @MainActor (String) -> Void = { [weak self] text in
            self?.liveOutput.append(text)
            // Keep only last 2000 chars to avoid memory bloat
            if let self = self, self.liveOutput.count > 2000 {
                self.liveOutput = String(self.liveOutput.suffix(2000))
            }
        }

        do {
            try Task.checkCancellation()
            update(message: "Preparing installer...", progress: 0.02)
            try copyManualScriptToApplicationSupport()

            try Task.checkCancellation()
            update(message: "Checking Homebrew...", progress: 0.05)
            if !Homebrew.isInstalled {
                update(message: "Installing Homebrew...", progress: 0.10)
                try await Homebrew.install(onOutput: outputHandler)
            }
            completedSteps.insert(.homebrew)

            try Task.checkCancellation()
            update(message: "Checking Python 3.13...", progress: 0.20)
            if !Python.isInstalled {
                update(message: "Installing Python 3.13...", progress: 0.25)
                try await Python.install(onOutput: outputHandler)
            }
            completedSteps.insert(.python)

            try Task.checkCancellation()
            update(message: "Checking uv...", progress: 0.35)
            if !Uv.isInstalled {
                update(message: "Installing uv...", progress: 0.40)
                try await Uv.install(onOutput: outputHandler)
            }
            completedSteps.insert(.uv)

            try Task.checkCancellation()
            update(message: "Checking Node.js...", progress: 0.50)
            if !Node.isInstalled {
                update(message: "Installing Node.js...", progress: 0.55)
                try await Node.install(onOutput: outputHandler)
            }
            completedSteps.insert(.node)

            try Task.checkCancellation()
            update(message: "Checking exo...", progress: 0.70)
            if !Exo.isInstalled {
                update(message: "Downloading exo...", progress: 0.75)
                try await Exo.clone(onOutput: outputHandler)
                update(message: "Creating Python environment...", progress: 0.80)
                try await Exo.createVenv(onOutput: outputHandler)
                update(message: "Building exo dashboard...", progress: 0.85)
                try await Exo.buildDashboard(onOutput: outputHandler)
            }
            completedSteps.insert(.exo)

            try Task.checkCancellation()
            update(message: "Finishing setup...", progress: 1.0)
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            if let depError = error as? DependencyError {
                self.error = depError
            } else if error is CancellationError {
                self.error = .cancelled
            } else {
                self.error = .missingTool(error.localizedDescription)
            }
        }
    }

    private func update(message: String, progress: Double) {
        self.message = message
        self.progress = progress
    }

    private func copyManualScriptToApplicationSupport() throws {
        let fm = FileManager.default
        let destDir = "\(NSHomeDirectory())/Library/Application Support/MacHive"
        let destPath = "\(destDir)/install-deps.sh"

        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true, attributes: nil)

        if fm.fileExists(atPath: destPath) {
            return
        }

        guard let bundlePath = Bundle.main.path(forResource: "install-deps", ofType: "sh") else {
            return
        }

        try? fm.removeItem(atPath: destPath)
        try fm.copyItem(atPath: bundlePath, toPath: destPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
    }
}

private enum Homebrew {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/brew") ||
        FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/.linuxbrew/bin/brew")
    }

    static var path: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") { return "/opt/homebrew/bin/brew" }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") { return "/usr/local/bin/brew" }
        return "\(NSHomeDirectory())/.linuxbrew/bin/brew"
    }

    static func install(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        let script = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        let result = await runShell(script, environment: [:], timeout: 600, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.homebrewInstallFailed(result.stderr.isEmpty ? "Install script exited with code \(result.terminationStatus)." : result.stderr)
        }
    }
}

private enum Python {
    static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/opt/homebrew/bin/python3.13") ||
               fm.fileExists(atPath: "/usr/local/bin/python3.13") ||
               fm.fileExists(atPath: "\(NSHomeDirectory())/.pyenv/shims/python3.13")
    }

    static func install(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        var env = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"]
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        let result = await runShell("\(Homebrew.path) install python@3.13 -v", environment: env, timeout: 300, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.pythonInstallFailed(result.stderr.isEmpty ? "brew install python@3.13 failed with code \(result.terminationStatus)." : result.stderr)
        }
    }
}

private enum Uv {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/uv") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/uv")
    }

    static func install(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        var env = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"]
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        let result = await runShell("\(Homebrew.path) install uv -v", environment: env, timeout: 300, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.uvInstallFailed(result.stderr.isEmpty ? "brew install uv failed with code \(result.terminationStatus)." : result.stderr)
        }
    }
}

private enum Node {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/node") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/node")
    }

    static func install(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        var env = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"]
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        let result = await runShell("\(Homebrew.path) install node -v", environment: env, timeout: 300, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.nodeInstallFailed(result.stderr.isEmpty ? "brew install node failed with code \(result.terminationStatus)." : result.stderr)
        }
    }
}

private enum Exo {
    static var installDirectory: String {
        "\(NSHomeDirectory())/Library/Application Support/MacHive/exo"
    }

    static var isInstalled: Bool {
        let fm = FileManager.default
        let mainPath = "\(installDirectory)/src/exo/main.py"
        let pyprojectPath = "\(installDirectory)/pyproject.toml"
        return fm.fileExists(atPath: mainPath) && fm.fileExists(atPath: pyprojectPath)
    }

    static func clone(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        let fm = FileManager.default
        let parent = "\(NSHomeDirectory())/Library/Application Support/MacHive"
        let exoDir = "\(parent)/exo"
        try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: exoDir) {
            try? fm.removeItem(atPath: exoDir)
        }
        let result = await runShell("git clone --depth 1 https://github.com/exo-explore/exo.git \"\(exoDir)\"", environment: ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"], timeout: 300, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.exoCloneFailed(result.stderr.isEmpty ? "git clone failed with code \(result.terminationStatus)." : result.stderr)
        }
    }

    static func createVenv(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        let result = await runShell("cd \"\(installDirectory)\" && uv venv && uv sync", environment: ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"], timeout: 600, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.exoBuildFailed(result.stderr.isEmpty ? "Python environment setup failed with code \(result.terminationStatus)." : result.stderr)
        }
    }

    static func buildDashboard(onOutput: (@MainActor (String) -> Void)? = nil) async throws {
        let dashboard = "\(installDirectory)/dashboard"
        let result = await runShell("cd \"\(dashboard)\" && npm install && npm run build", environment: ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"], timeout: 600, onOutput: onOutput)
        if result.terminationStatus != 0 {
            throw DependencyError.exoBuildFailed(result.stderr.isEmpty ? "Dashboard build failed with code \(result.terminationStatus)." : result.stderr)
        }
    }
}

struct ShellResult {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

func runShell(_ command: String, environment: [String: String], timeout: TimeInterval, onOutput: (@MainActor (String) -> Void)? = nil) async -> ShellResult {
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-c", command]
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            task.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            var stdout = ""
            var stderr = ""
            var hasResumed = false
            let lock = NSLock()

            func finish() {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                if let finalOut = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    stdout.append(finalOut)
                }
                if let finalErr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    stderr.append(finalErr)
                }

                continuation.resume(returning: ShellResult(
                    stdout: stdout,
                    stderr: stderr,
                    terminationStatus: task.terminationStatus
                ))
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let text = String(data: data, encoding: .utf8) {
                    stdout.append(text)
                    DispatchQueue.main.async {
                        onOutput?(text)
                    }
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let text = String(data: data, encoding: .utf8) {
                    stderr.append(text)
                    DispatchQueue.main.async {
                        onOutput?(text)
                    }
                }
            }

            task.terminationHandler = { task in
                finish()
            }

            let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.setEventHandler {
                if task.isRunning {
                    task.terminate()
                }
                // If terminate doesn't kill it, force kill after 2 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if task.isRunning {
                        kill(task.processIdentifier, SIGKILL)
                    }
                    finish()
                }
            }
            timeoutTimer.resume()

            do {
                try task.run()
            } catch {
                stderr = error.localizedDescription
                timeoutTimer.cancel()
                finish()
            }
        }
    }
}
