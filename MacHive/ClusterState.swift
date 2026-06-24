import Foundation
import Darwin

enum ClusterStatus: Equatable {
    case notRunning
    case starting
    case ready
    case running
    case error(String)

    var display: String {
        switch self {
        case .notRunning: return "Not running"
        case .starting: return "Starting..."
        case .ready: return "Ready"
        case .running: return "Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

enum ExoModel: String, CaseIterable, Identifiable {
    case llama3_8b = "Llama 3 8B"
    case llama3_70b = "Llama 3 70B"
    case llama3_1_405b = "Llama 3.1 405B"
    case qwen2_5_32b = "Qwen 2.5 32B"
    case qwen2_5_72b = "Qwen 2.5 72B"
    case mistral_7b = "Mistral 7B"
    case mixtral_8x22b = "Mixtral 8x22B"
    case deepseek_r1_32b = "DeepSeek R1 32B"
    case deepseek_r1_70b = "DeepSeek R1 70B"

    var id: String { rawValue }

    // Estimated RAM required to load the 4-bit quantized model weights.
    // These are conservative real-world values for exo's default mlx-community models.
    var requiredRAMGB: Int {
        switch self {
        case .llama3_8b: return 8
        case .llama3_70b: return 40
        case .llama3_1_405b: return 230
        case .qwen2_5_32b: return 20
        case .qwen2_5_72b: return 45
        case .mistral_7b: return 8
        case .mixtral_8x22b: return 80
        case .deepseek_r1_32b: return 22
        case .deepseek_r1_70b: return 48
        }
    }
}

struct Peer: Identifiable, Hashable {
    let id: String
    let name: String
    let ramGB: Int
    let chip: String
    let macModel: String
    let osVersion: String
    let ipAddress: String
    let namespace: String
    let isOnline: Bool
    var lastSeen: Date

    static func == (lhs: Peer, rhs: Peer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayInfo: String {
        "\(chip) · \(ramGB) GB RAM · \(macModel) · macOS \(osVersion)"
    }
}

@MainActor
final class ClusterState: ObservableObject {
    @Published var status: ClusterStatus = .notRunning
    @Published var peers: [Peer] = []
    @Published var selectedModel: ExoModel = UserDefaults.standard.exoModel {
        didSet { UserDefaults.standard.exoModel = selectedModel }
    }
    @Published var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled() {
        didSet { LaunchAtLoginManager.setEnabled(launchAtLogin) }
    }
    @Published var autoStartCluster: Bool = UserDefaults.standard.bool(forKey: "autoStartCluster") {
        didSet { UserDefaults.standard.set(autoStartCluster, forKey: "autoStartCluster") }
    }
    @Published var showAdvancedSettings: Bool = false
    @Published var namespace: String = UserDefaults.standard.string(forKey: "exoNamespace") ?? "machive" {
        didSet { UserDefaults.standard.set(namespace, forKey: "exoNamespace") }
    }
    @Published var showExoLogs: Bool = false

    var localPeer: Peer {
        Peer(
            id: Host.current().localizedName ?? UUID().uuidString,
            name: Host.current().localizedName ?? "This Mac",
            ramGB: SystemInfo.totalRAMGB,
            chip: SystemInfo.chipModel,
            macModel: SystemInfo.macModel,
            osVersion: SystemInfo.osVersion,
            ipAddress: NetworkHelper.getLocalIPAddress() ?? "Unknown",
            namespace: namespace,
            isOnline: true,
            lastSeen: Date()
        )
    }

    var combinedRAMGB: Int {
        // Always include the local peer with its real RAM, plus any remote online peers
        let remoteOnline = peers.filter { $0.isOnline && $0.id != localPeer.id }
        return localPeer.ramGB + remoteOnline.reduce(0) { $0 + $1.ramGB }
    }

    var onlinePeerCount: Int {
        let remoteOnline = peers.filter { $0.isOnline && $0.id != localPeer.id }
        return 1 + remoteOnline.count
    }

    var selectedModelFits: Bool {
        combinedRAMGB >= selectedModel.requiredRAMGB
    }

    var clusterReady: Bool {
        let multiplePeers = onlinePeerCount >= 2
        return (status == .running || status == .ready) && multiplePeers && selectedModelFits
    }

    func canRunModel(_ model: ExoModel) -> Bool {
        combinedRAMGB >= model.requiredRAMGB
    }
}

extension UserDefaults {
    var exoModel: ExoModel {
        get {
            if let raw = string(forKey: "exoModel"), let value = ExoModel(rawValue: raw) {
                return value
            }
            return .llama3_8b
        }
        set {
            set(newValue.rawValue, forKey: "exoModel")
        }
    }
}

enum SystemInfo {
    static var totalRAMGB: Int {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return max(1, Int(bytes / (1024 * 1024 * 1024)))
    }

    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("hw.model", &buffer, &size, nil, 0)
        guard result == 0 else { return "Mac" }
        return String(cString: buffer)
            .replacingOccurrences(of: ",", with: " ")
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var chipModel: String {
        var size = 0
        let key = "machdep.cpu.brand_string"
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname(key, &buffer, &size, nil, 0)
        guard result == 0 else { return "Apple Silicon" }
        let brand = String(cString: buffer)
        let known = ["M1", "M2", "M3", "M4"]
        for gen in known where brand.contains(gen) {
            return gen
        }
        if brand.contains("Apple") {
            return "Apple Silicon"
        }
        return brand
    }
}
