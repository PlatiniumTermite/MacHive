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

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    @Published var setupComplete = false
    private var hostingController: NSHostingController<AnyView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if setupComplete {
            MenuBarView()
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
