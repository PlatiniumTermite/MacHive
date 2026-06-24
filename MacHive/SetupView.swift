import SwiftUI
import AppKit

struct SetupView: View {
    @StateObject private var installer = DependencyInstaller()
    @Binding var isComplete: Bool
    @State private var hasStarted = false
    @State private var terminalOpened = false

    var body: some View {
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
                    terminalOpened = true
                    installer.openTerminalAndInstall()
                }
            }
        }
        .onAppear {
            if !installer.isComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !hasStarted {
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
        VStack(spacing: 20) {
            Text("Welcome to MacHive")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                stepRow(icon: "1.circle.fill", text: "Install Homebrew")
                stepRow(icon: "2.circle.fill", text: "Install Python 3.13, uv, Node.js")
                stepRow(icon: "3.circle.fill", text: "Download and prepare exo")
                stepRow(icon: "4.circle.fill", text: "Build the exo dashboard")
            }
            .frame(width: 280)

            Text("This takes 10–30 minutes on first launch. MacHive can install everything in the background, or open Terminal and run it automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 280)
                .multilineTextAlignment(.center)

            Button("Install Automatically") {
                withAnimation {
                    hasStarted = true
                }
                installer.startInstallation()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Run in Terminal") {
                installer.openTerminalAndInstall()
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private var setupContent: some View {
        VStack(spacing: 20) {
            Text("Setting up MacHive...")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                ProgressView(value: installer.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 280)

                Text(installer.message)
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
                        installer.startInstallation()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    if terminalOpened {
                        Text("Terminal opened automatically. Enter your admin password if asked.")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .frame(width: 280)
                            .multilineTextAlignment(.center)
                    } else {
                        Button("Run in Terminal") {
                            terminalOpened = true
                            installer.openTerminalAndInstall()
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
}

#Preview {
    SetupView(isComplete: .constant(false))
}
