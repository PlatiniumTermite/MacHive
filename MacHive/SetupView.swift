import SwiftUI
import AppKit

struct SetupView: View {
    @StateObject private var installer = DependencyInstaller()
    @Binding var isComplete: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hexagon.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)

            Text("Setting up MacHive...")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ProgressView(value: installer.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 280)

                Text(installer.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 280)
                    .multilineTextAlignment(.center)
            }

            if let error = installer.error {
                VStack(spacing: 8) {
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
                        installer.startInstallation()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Copy Manual Command") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(installer.manualInstallCommand, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
        .padding(32)
        .frame(width: 360)
        .onAppear {
            installer.startInstallation()
        }
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
            }
        }
    }
}

#Preview {
    SetupView(isComplete: .constant(false))
}
