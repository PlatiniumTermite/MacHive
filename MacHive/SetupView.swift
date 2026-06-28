import SwiftUI
import AppKit

struct SetupView: View {
    @StateObject private var installer = DependencyInstaller()
    @Binding var isComplete: Bool
    @State private var hasStarted = false
    @State private var terminalOpened = false
    @State private var completionTimer: Timer?
    @State private var terminalError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "hexagon.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.accentColor)

                if !hasStarted {
                    welcomeContent
                } else {
                    setupContent
                }
            }
            .padding(32)
            .frame(width: 380)
        }
        .frame(width: 380, height: 480)
        .onChange(of: installer.isComplete) { complete in
            if complete {
                withAnimation {
                    isComplete = true
                }
            }
        }
        .onChange(of: installer.error) { _ in
            if installer.error != nil {
                installer.isRunning = false
                if !terminalOpened {
                    if installer.openTerminalAndInstall() {
                        terminalOpened = true
                        startCompletionPolling()
                    } else {
                        terminalError = "MacHive needs permission to open Terminal. Please allow it in System Settings > Privacy & Security > Automation, or copy the manual command below."
                    }
                }
            }
        }
        .alert("Could not open Terminal", isPresented: Binding(get: { terminalError != nil }, set: { if !$0 { terminalError = nil } })) {
            Button("OK", role: .cancel) { }
            Button("Copy Manual Command") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(installer.manualInstallCommand, forType: .string)
            }
        } message: {
            Text(terminalError ?? "")
        }
        .onDisappear {
            completionTimer?.invalidate()
            completionTimer = nil
        }
        .onAppear {
            if !installer.isComplete && !hasStarted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if installer.isHomebrewMissing {
                        withAnimation {
                            hasStarted = true
                        }
                        if installer.openTerminalAndInstall() {
                            terminalOpened = true
                            startCompletionPolling()
                        } else {
                            terminalError = "MacHive needs permission to open Terminal. Please allow it in System Settings > Privacy & Security > Automation, or copy the manual command below."
                        }
                    } else {
                        withAnimation {
                            hasStarted = true
                        }
                        installer.startInstallation()
                    }
                }
            }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 18) {
            Text("Welcome to MacHive")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Share CPU and RAM across your Macs for AI.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                stepRow(icon: "1.circle.fill", text: "Install Homebrew")
                stepRow(icon: "2.circle.fill", text: "Install Python 3.13, uv, Node.js")
                stepRow(icon: "3.circle.fill", text: "Download and prepare exo")
                stepRow(icon: "4.circle.fill", text: "Build the exo dashboard")
            }
            .frame(width: 280)

            VStack(alignment: .leading, spacing: 8) {
                Text("What happens now")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("MacHive will install everything automatically. On a brand new Mac, Terminal opens and asks for your admin password. After that, you can walk away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Typical time: 10–30 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("If Terminal does not open, click the copy button below and paste the command into Terminal yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 280)

            if installer.isHomebrewMissing {
                Button("Install in Terminal") {
                    withAnimation {
                        hasStarted = true
                    }
                    if installer.openTerminalAndInstall() {
                        terminalOpened = true
                        startCompletionPolling()
                    } else {
                        terminalError = "MacHive needs permission to open Terminal. Please allow it in System Settings > Privacy & Security > Automation, or copy the manual command below."
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Install Automatically") {
                    withAnimation {
                        hasStarted = true
                    }
                    installer.startInstallation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button("Run in Terminal") {
                if installer.openTerminalAndInstall() {
                    terminalOpened = true
                    withAnimation {
                        hasStarted = true
                    }
                    startCompletionPolling()
                } else {
                    terminalError = "MacHive needs permission to open Terminal. Please allow it in System Settings > Privacy & Security > Automation, or copy the manual command below."
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private func startCompletionPolling() {
        completionTimer?.invalidate()
        completionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                if installer.isComplete {
                    completionTimer?.invalidate()
                    completionTimer = nil
                    withAnimation {
                        isComplete = true
                    }
                }
            }
        }
    }

    private var setupContent: some View {
        VStack(spacing: 20) {
            Text(terminalOpened ? "Installing in Terminal..." : "Setting up MacHive...")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                ProgressView(value: installer.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 280)

                Text(terminalOpened ? "Terminal is open. Enter your admin password if asked. MacHive will continue automatically when done." : installer.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 280)
                    .multilineTextAlignment(.center)

                if !installer.liveOutput.isEmpty {
                    ScrollView {
                        Text(installer.liveOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 260, alignment: .leading)
                            .lineLimit(nil)
                            .padding(6)
                    }
                    .frame(width: 280, height: 100)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SetupStep.allCases, id: \.self) { step in
                        HStack(spacing: 8) {
                            Image(systemName: installer.completedSteps.contains(step) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(installer.completedSteps.contains(step) ? .green : .secondary)
                                .font(.callout)
                                .animation(.easeInOut(duration: 0.2), value: installer.completedSteps.contains(step))
                            Text(step.rawValue)
                                .font(.callout)
                                .foregroundStyle(installer.completedSteps.contains(step) ? .primary : .secondary)
                            Spacer()
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 200)
            }

            if installer.isComplete && installer.error == nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Setup complete. MacHive is ready.")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }

            if let error = installer.error {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error.localizedDescription)
                    }
                    .font(.callout)
                    .foregroundColor(.red)
                    .frame(width: 280)
                    .multilineTextAlignment(.center)

                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 280)
                            .multilineTextAlignment(.center)
                    }

                    Button("Try Again") {
                        terminalOpened = false
                        completionTimer?.invalidate()
                        completionTimer = nil
                        installer.startInstallation()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button("Open Setup Log") {
                        openSetupLog()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if terminalOpened {
                        Text("Terminal opened automatically. Enter your admin password if asked.")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .frame(width: 280)
                            .multilineTextAlignment(.center)
                    } else {
                        Button("Run in Terminal") {
                            if installer.openTerminalAndInstall() {
                                terminalOpened = true
                                startCompletionPolling()
                            } else {
                                terminalError = "MacHive needs permission to open Terminal. Please allow it in System Settings > Privacy & Security > Automation, or copy the manual command below."
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func stepRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
            Text(text)
                .font(.callout)
            Spacer()
        }
    }

    private func openSetupLog() {
        let logPath = DependencyInstaller.logFilePath
        let fm = FileManager.default
        if !fm.fileExists(atPath: logPath) {
            try? "MacHive setup log\n".write(toFile: logPath, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
}

#Preview {
    SetupView(isComplete: .constant(false))
}
