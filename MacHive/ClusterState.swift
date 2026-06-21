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
    case qwen2_5_32b = "Qwen 2.5 32B"
    case mistral_7b = "Mistral 7B"

    var id: String { rawValue }

    // Estimated RAM required to load the 4-bit quantized model weights.
    // These are conservative real-world values for exo's default mlx-community models.
    var requiredRAMGB: Int {
        switch self {
        case .llama3_8b: return 8
        case .llama3_70b: return 40
        case .qwen2_5_32b: return 20
        case .mistral_7b: return 8
        }
    }
}

struct Peer: Identifiable, Hashable {
    let id: String
    let name: String
    let ramGB: Int
    let chip: String
    let isOnline: Bool
    var lastSeen: Date

    static func == (lhs: Peer, rhs: Peer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class ClusterState: ObservableObject {
    @Published var status: ClusterStatus = .notRunning
    @Published var peers: [Peer] = []
    @Published var selectedModel: ExoModel = .llama3_8b
    @Published var launchAtLogin: Bool = false

    var localPeer: Peer {
        Peer(
            id: Host.current().localizedName ?? UUID().uuidString,
            name: Host.current().localizedName ?? "This Mac",
            ramGB: SystemInfo.totalRAMGB,
            chip: SystemInfo.chipModel,
            isOnline: true,
            lastSeen: Date()
        )
    }

    var combinedRAMGB: Int {
        let online = peers.filter(\.isOnline)
        return online.reduce(0) { $0 + $1.ramGB }
    }

    var onlinePeerCount: Int {
        peers.filter(\.isOnline).count
    }

    var selectedModelFits: Bool {
        combinedRAMGB >= selectedModel.requiredRAMGB
    }

    func canRunModel(_ model: ExoModel) -> Bool {
        combinedRAMGB >= model.requiredRAMGB
    }
}

enum SystemInfo {
    static var totalRAMGB: Int {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return max(1, Int(bytes / (1024 * 1024 * 1024)))
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
