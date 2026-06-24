import SwiftUI
import AppKit
import ServiceManagement
import Combine
import QuartzCore
import UserNotifications

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
    private var animatedIcon: AnimatedStatusIcon?
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
    private var cancellables = Set<AnyCancellable>()
    let sharedDiscovery = PeerDiscovery()
    let sharedExo = ExoManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !isInApplicationsFolder() {
            showMoveToApplicationsAlert()
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let icon = AnimatedStatusIcon(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
            button.addSubview(icon)
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 22)
            ])
            icon.status = .idle
            self.animatedIcon = icon
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(requestLocalNetwork),
            name: NSNotification.Name("MacHiveRequestLocalNetwork"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkForUpdatesManual),
            name: NSNotification.Name("MacHiveCheckForUpdates"),
            object: nil
        )

        sharedExo.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        sharedExo.$isPreparing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        var previousPeers: Set<String> = []
        sharedDiscovery.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                UserDefaults.standard.set(peers.count, forKey: "MacHivePeerCount")
                self?.updateIcon()
                let currentIDs = Set(peers.map { $0.id })
                let joined = currentIDs.subtracting(previousPeers)
                let left = previousPeers.subtracting(currentIDs)
                for id in joined {
                    if let peer = peers.first(where: { $0.id == id }) {
                        self?.postNotification(title: "Mac joined", body: "\(peer.name) is now in the cluster")
                    }
                }
                for _ in left {
                    self?.postNotification(title: "Mac left", body: "A Mac disconnected from the cluster")
                }
                previousPeers = currentIDs
            }
            .store(in: &cancellables)

        if #available(macOS 11.0, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        Task { @MainActor in
            let installer = DependencyInstaller()
            if installer.isComplete {
                setupComplete = true
                rebuildPopover()
                await sharedExo.checkExistingExo()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.checkForUpdates()
                }
            }
        }
    }

    private func checkForUpdates() {
        let url = URL(string: "https://api.github.com/repos/PlatiniumTermite/MacHive/releases/latest")!
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tag = json["tag_name"] as? String {
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                    let latest = tag.replacingOccurrences(of: "v", with: "")
                    if latest.compare(currentVersion, options: .numeric) == .orderedDescending {
                        await MainActor.run {
                            self.showUpdateAlert(version: latest)
                        }
                    }
                }
            } catch {
                NSLog("MacHive: update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func showUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "MacHive \(version) is available"
        alert.informativeText = "A newer version of MacHive has been released. Download it to get the latest improvements."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/PlatiniumTermite/MacHive/releases/latest")!)
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
        guard let icon = animatedIcon else { return }
        let running = UserDefaults.standard.bool(forKey: "MacHiveClusterRunning")
        let peers = UserDefaults.standard.integer(forKey: "MacHivePeerCount")
        if running {
            icon.status = peers > 0 ? .connected : .searching
        } else {
            icon.status = sharedExo.isPreparing ? .connecting : .idle
        }
    }

    @objc private func requestLocalNetwork() {
        sharedDiscovery.start()
        sharedDiscovery.forceDiscovery()
    }

    @objc private func checkForUpdatesManual() {
        checkForUpdates()
    }

    private func postNotification(title: String, body: String) {
        if #available(macOS 11.0, *) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = body
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
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

// MARK: - Animated Status Icon

final class AnimatedStatusIcon: NSView {
    enum IconStatus {
        case idle
        case connecting
        case searching
        case connected
    }

    var status: IconStatus = .idle {
        didSet { updateAppearance() }
    }

    private let hexagonLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private var rotationAnimation: CABasicAnimation?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupLayers()
    }

    override func layout() {
        super.layout()
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let hexRadius = size * 0.30
        let ringRadius = size * 0.42

        hexagonLayer.path = hexagonPath(center: center, radius: hexRadius).cgPath
        ringLayer.path = circlePath(center: center, radius: ringRadius).cgPath
    }

    private func setupLayers() {
        hexagonLayer.fillColor = NSColor.secondaryLabelColor.cgColor
        hexagonLayer.strokeColor = NSColor.clear.cgColor
        hexagonLayer.lineWidth = 0
        layer?.addSublayer(hexagonLayer)

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor.tertiaryLabelColor.cgColor
        ringLayer.lineWidth = 1.2
        ringLayer.lineDashPattern = [3, 4]
        ringLayer.opacity = 0.6
        layer?.addSublayer(ringLayer)

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.95
        breathe.toValue = 1.05
        breathe.duration = 2.0
        breathe.autoreverses = true
        breathe.repeatCount = .greatestFiniteMagnitude
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hexagonLayer.add(breathe, forKey: "breathe")

        updateAppearance()
    }

    private func updateAppearance() {
        let color: NSColor
        let ringOpacity: Float
        let rotate: Bool
        switch status {
        case .idle:
            color = NSColor.secondaryLabelColor
            ringOpacity = 0.4
            rotate = false
        case .connecting:
            color = NSColor.systemOrange
            ringOpacity = 0.7
            rotate = true
        case .searching:
            color = NSColor.systemYellow
            ringOpacity = 0.7
            rotate = true
        case .connected:
            color = NSColor.systemGreen
            ringOpacity = 0.9
            rotate = false
        }

        hexagonLayer.fillColor = color.cgColor
        ringLayer.strokeColor = color.cgColor
        ringLayer.opacity = ringOpacity

        if rotate, rotationAnimation == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = Double.pi * 2
            rotation.duration = 6
            rotation.repeatCount = .greatestFiniteMagnitude
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            ringLayer.add(rotation, forKey: "rotate")
            rotationAnimation = rotation
        } else if !rotate {
            ringLayer.removeAnimation(forKey: "rotate")
            rotationAnimation = nil
        }
    }

    private func hexagonPath(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<6 {
            let angle = CGFloat(i) * CGFloat.pi / 3 - CGFloat.pi / 2
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.line(to: CGPoint(x: x, y: y)) }
        }
        path.close()
        return path
    }

    private func circlePath(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        return NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}
