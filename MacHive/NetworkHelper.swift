import Foundation
import Network

@MainActor
final class NetworkHelper {
    static func checkNetworkRequirements() -> [String] {
        var issues: [String] = []
        
        // Check if firewall is blocking
        if isFirewallEnabled() {
            issues.append("macOS Firewall is enabled. It may block peer discovery. Go to System Settings → Network → Firewall and add MacHive to allowed apps.")
        }
        
        // Check if on WiFi
        if !isOnWiFi() {
            issues.append("Not connected to WiFi. Peer discovery requires all Macs on the same WiFi network.")
        }
        
        return issues
    }
    
    static func isFirewallEnabled() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "/Library/Preferences/com.apple.alf", "globalstate"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.availableData
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return text != "0"
            }
        } catch {
            return false
        }
        return false
    }
    
    static func isOnWiFi() -> Bool {
        let monitor = NWPathMonitor()
        let resultBox = ResultBox<Bool>(value: false)
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            resultBox.value = path.usesInterfaceType(.wifi)
            semaphore.signal()
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()
        return resultBox.value
    }

    private final class ResultBox<T> {
        var value: T
        init(value: T) {
            self.value = value
        }
    }
    
    nonisolated static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // WiFi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
