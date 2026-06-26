import SwiftUI

struct WelcomeSetupSheet: View {
    @Binding var isPresented: Bool
    @State private var isInApplications = false
    @State private var isFirewallOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hexagon.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacHive Setup")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Complete these steps for perfect performance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isInApplications ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(isInApplications ? .green : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Move MacHive to /Applications")
                            .font(.headline)
                        Text("Required for network permissions and local discovery.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !isInApplications {
                            Button("Move to /Applications") {
                                moveToApplications()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isFirewallOn ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isFirewallOn ? .orange : .green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Turn off macOS Firewall")
                            .font(.headline)
                        Text("The firewall blocks MacHive from discovering other Macs on the same network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isFirewallOn {
                            Button("Open Firewall Settings") {
                                FirewallHelper.openFirewallSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect all Macs to the same WiFi")
                            .font(.headline)
                        Text("All Macs must be on the same local network. Avoid guest networks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Local Network access")
                            .font(.headline)
                        Text("macOS will ask once. Click Allow so MacHive can find your other Macs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Request Local Network Access") {
                            NotificationCenter.default.post(name: NSNotification.Name("MacHiveRequestLocalNetwork"), object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            Button("Done") {
                isPresented = false
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            refreshChecks()
            // Auto-trigger the system Local Network permission dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: NSNotification.Name("MacHiveRequestLocalNetwork"), object: nil)
            }
        }
    }

    private func refreshChecks() {
        isInApplications = Bundle.main.bundlePath.hasPrefix("/Applications/")

        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "/Library/Preferences/com.apple.alf", "globalstate"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1"
        isFirewallOn = text != "0"
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
}
