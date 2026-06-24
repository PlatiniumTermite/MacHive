import SwiftUI
import AppKit
import ServiceManagement

@main
struct MacHiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    @Published var setupComplete = false {
        didSet {
            if setupComplete && !autoStartHandled {
                autoStartHandled = true
                sharedDiscovery.start()
                if UserDefaults.standard.bool(forKey: "autoStartCluster"), !sharedExo.isRunning, !sharedExo.isPreparing {
                    sharedExo.start(namespace: UserDefaults.standard.string(forKey: "exoNamespace") ?? "machive")
                }
            }
        }
    }
    private var autoStartHandled = false
    private var hostingController: NSHostingController<AnyView>?
    let sharedDiscovery = PeerDiscovery()
    let sharedExo = ExoManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !isInApplicationsFolder() {
            showMoveToApplicationsAlert()
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hexagon.fill", accessibilityDescription: "MacHive")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        rebuildPopover()

        updateIcon()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIcon),
            name: NSNotification.Name("MacHiveStatusChanged"),
            object: nil
        )

        Task { @MainActor in
            let installer = DependencyInstaller()
            if installer.isComplete {
                setupComplete = true
                rebuildPopover()
                await sharedExo.checkExistingExo()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if setupComplete {
            MenuBarView(discovery: sharedDiscovery, exo: sharedExo)
        } else {
            let binding = Binding<Bool>(
                get: { self.setupComplete },
                set: { newValue in
                    self.setupComplete = newValue
                    if newValue { self.rebuildPopover() }
                }
            )
            SetupView(isComplete: binding)
        }
    }

    private func rebuildPopover() {
        if let controller = hostingController {
            controller.rootView = AnyView(contentView)
        } else {
            let controller = NSHostingController(rootView: AnyView(contentView))
            hostingController = controller
            popover.contentViewController = controller
        }
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.close()
                NSApp.deactivate()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc private func updateIcon() {
        guard let button = statusItem.button else { return }
        let running = UserDefaults.standard.bool(forKey: "MacHiveClusterRunning")
        let symbolName = running ? "hexagon.fill" : "hexagon"
        let color = running ? NSColor.systemGreen : NSColor.secondaryLabelColor
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MacHive") {
            image.isTemplate = false
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            button.image = image.withSymbolConfiguration(config)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func isInApplicationsFolder() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return false }
        return bundlePath.hasPrefix("/Applications/")
    }

    private func showMoveToApplicationsAlert() {
        let alert = NSAlert()
        alert.messageText = "Move MacHive to Applications"
        alert.informativeText = "MacHive must run from /Applications to work correctly. Click Move to move it automatically, or move it manually and relaunch."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Move Manually Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            moveToApplicationsAndRelaunch()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func moveToApplicationsAndRelaunch() {
        guard let sourceURL = Bundle.main.bundleURL as URL? else {
            showMoveFailedAlert(message: "Could not locate MacHive.app.")
            return
        }
        let destinationURL = URL(fileURLWithPath: "/Applications/MacHive.app")
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: destinationURL.path) {
                try? fm.trashItem(at: destinationURL, resultingItemURL: nil)
            }
            try fm.copyItem(at: sourceURL, to: destinationURL)

            let alert = NSAlert()
            alert.messageText = "MacHive moved to Applications"
            alert.informativeText = "MacHive will now relaunch from /Applications."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Relaunch")
            alert.runModal()

            NSWorkspace.shared.openApplication(at: destinationURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                NSApp.terminate(nil)
            }
        } catch {
            showMoveFailedAlert(message: error.localizedDescription)
        }
    }

    private func showMoveFailedAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not move automatically"
        alert.informativeText = "Please drag MacHive.app to /Applications manually and relaunch. Error: \(message)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

enum LaunchAtLoginManager {
    @available(macOS 13.0, *)
    private static var mainAppService: SMAppService {
        SMAppService.mainApp
    }

    static func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return mainAppService.status == .enabled
        } else {
            return false
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if mainAppService.status != .enabled {
                    try mainAppService.register()
                }
            } else {
                if mainAppService.status == .enabled {
                    try mainAppService.unregister()
                }
            }
        } catch {
            NSLog("MacHive: launch-at-login error: \(error.localizedDescription)")
        }
    }
}
