import Foundation
import AppKit

enum FirewallHelper {
    static func openFirewallSettings() {
        // Try multiple methods because the URL scheme changes between macOS versions
        let urls = [
            "x-apple.systempreferences:com.apple.security.firewall",
            "x-apple.systempreferences:com.apple.Security-Settings.extension.Firewall",
            "x-apple.systempreferences:com.apple.preference.security?Firewall"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
        // Fallback: open System Settings directly
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-b", "com.apple.systempreferences", "x-apple.systempreferences:com.apple.security.firewall"]
        try? task.run()
    }
}
