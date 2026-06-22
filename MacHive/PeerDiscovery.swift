import Foundation
import Network

final class PeerDiscovery: ObservableObject {
    static let serviceType = "_machive._tcp"
    static let domain = "local."
    static let cleanupInterval: TimeInterval = 2.0
    static let timeout: TimeInterval = 5.0
    static let udpPort: UInt16 = 52416
    static let broadcastInterval: TimeInterval = 2.0

    private var advertiser: NWListener?
    private var browser: NWBrowser?
    private var cleanupTimer: Timer?
    private var udpBroadcastTimer: Timer?
    private var udpListener: NWListener?
    private var udpConnection: NWConnection?
    private var discovered: [String: Peer] = [:]
    private let updateQueue = DispatchQueue(label: "com.machive.peerdiscovery", qos: .utility)

    @Published var peers: [Peer] = []
    @Published var error: String? = nil
    @Published var isBrowsing: Bool = false

    func start() {
        error = nil
        startAdvertising()
        startBrowsing()
        startUDPFallback()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: PeerDiscovery.cleanupInterval, repeats: true) { [weak self] _ in
            self?.purgeStalePeers()
        }
    }

    func stop() {
        advertiser?.cancel()
        advertiser = nil
        browser?.cancel()
        browser = nil
        udpListener?.cancel()
        udpListener = nil
        udpConnection?.cancel()
        udpConnection = nil
        udpBroadcastTimer?.invalidate()
        udpBroadcastTimer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        isBrowsing = false
        updateQueue.async { [weak self] in
            self?.discovered.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.peers.removeAll()
            }
        }
    }

    func refresh() {
        stop()
        start()
    }

    private func startAdvertising() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        do {
            advertiser = try NWListener(using: parameters, on: 0)
        } catch {
            NSLog("MacHive: failed to create advertiser: \(error.localizedDescription)")
            return
        }

        advertiser?.service = NWListener.Service(
            name: Host.current().localizedName ?? "MacHive",
            type: PeerDiscovery.serviceType,
            domain: PeerDiscovery.domain,
            txtRecord: txtRecord()
        )

        advertiser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .failed(let error) = state {
                NSLog("MacHive: advertiser failed: \(error.localizedDescription)")
                self.advertiser?.cancel()
                self.advertiser = nil
            }
        }

        advertiser?.newConnectionHandler = { connection in
            connection.start(queue: .global())
        }

        advertiser?.start(queue: .global())
    }

    private func txtRecord() -> NWTXTRecord {
        let ram = "\(SystemInfo.totalRAMGB)"
        let chip = SystemInfo.chipModel
        var record = NWTXTRecord()
        record["ram"] = ram
        record["chip"] = chip
        record["status"] = "online"
        return record
    }

    private func startBrowsing() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true

        browser = NWBrowser(for: .bonjour(type: PeerDiscovery.serviceType, domain: PeerDiscovery.domain), using: parameters)
        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async { [weak self] in
                switch state {
                case .ready:
                    self?.isBrowsing = true
                    self?.error = nil
                case .failed(let error):
                    self?.isBrowsing = false
                    let msg = "Peer discovery failed: \(error.localizedDescription)"
                    self?.error = msg
                    NSLog("MacHive: \(msg)")
                case .cancelled:
                    self?.isBrowsing = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.updateQueue.async { [weak self] in
                self?.handle(results: results)
            }
        }
        browser?.start(queue: .global())
    }

    private func startUDPFallback() {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: PeerDiscovery.udpPort) else {
            NSLog("MacHive: invalid UDP port")
            return
        }

        do {
            udpListener = try NWListener(using: parameters, on: port)
        } catch {
            NSLog("MacHive: UDP listener failed: \(error.localizedDescription)")
            return
        }

        udpListener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            connection.receiveMessage { [weak self] content, _, _, error in
                if let data = content, let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    self?.updateQueue.async { [weak self] in
                        self?.handleUDP(payload: payload)
                    }
                }
                if error == nil {
                    self?.udpListen(connection: connection)
                }
            }
        }
        udpListener?.start(queue: .global())

        guard let broadcastIP = IPv4Address("255.255.255.255") else {
            NSLog("MacHive: invalid broadcast IP")
            return
        }
        let endpoint = NWEndpoint.hostPort(host: .ipv4(broadcastIP), port: port)
        udpConnection = NWConnection(to: endpoint, using: parameters)
        udpConnection?.start(queue: .global())

        udpBroadcastTimer = Timer.scheduledTimer(withTimeInterval: PeerDiscovery.broadcastInterval, repeats: true) { [weak self] _ in
            self?.sendUDPBroadcast()
        }
        sendUDPBroadcast()
    }

    private func udpListen(connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            if let data = content, let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                self?.updateQueue.async { [weak self] in
                    self?.handleUDP(payload: payload)
                }
            }
            if error == nil {
                self?.udpListen(connection: connection)
            }
        }
    }

    private func sendUDPBroadcast() {
        let payload: [String: String] = [
            "name": Host.current().localizedName ?? "MacHive",
            "ram": "\(SystemInfo.totalRAMGB)",
            "chip": SystemInfo.chipModel,
            "status": "online"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        udpConnection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                NSLog("MacHive: UDP broadcast failed: \(error.localizedDescription)")
            }
        })
    }

    private func handleUDP(payload: [String: String]) {
        let name = payload["name"] ?? "Unknown Mac"
        let peer = Peer(
            id: name,
            name: name,
            ramGB: parseInt(payload["ram"] ?? "0"),
            chip: payload["chip"] ?? "Apple Silicon",
            isOnline: true,
            lastSeen: Date()
        )
        discovered[name] = peer
        DispatchQueue.main.async { [weak self] in
            self?.updatePeers()
        }
    }

    private func handle(results: Set<NWBrowser.Result>) {
        let currentNames = Set(results.compactMap { resultName($0.endpoint) })
        let removed = Set(discovered.keys).subtracting(currentNames)
        for name in removed {
            discovered.removeValue(forKey: name)
        }

        for result in results {
            guard let name = resultName(result.endpoint) else { continue }
            let txt = extractTXTRecord(from: result)
            let peer = Peer(
                id: name,
                name: name,
                ramGB: parseInt(txt["ram"] ?? "0"),
                chip: txt["chip"] ?? "Apple Silicon",
                isOnline: true,
                lastSeen: Date()
            )
            discovered[name] = peer
        }

        DispatchQueue.main.async { [weak self] in
            self?.updatePeers()
        }
    }

    private func updatePeers() {
        let list = Array(discovered.values)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var peers = list
            let local = ClusterState().localPeer
            if !peers.contains(where: { $0.id == local.id }) {
                peers.append(local)
            }
            peers.sort { $0.name < $1.name }
            self.peers = peers
        }
    }

    private func purgeStalePeers() {
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            for (id, peer) in self.discovered where now.timeIntervalSince(peer.lastSeen) > PeerDiscovery.timeout {
                self.discovered[id] = Peer(
                    id: peer.id,
                    name: peer.name,
                    ramGB: peer.ramGB,
                    chip: peer.chip,
                    isOnline: false,
                    lastSeen: peer.lastSeen
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?.updatePeers()
            }
        }
    }
}

private func resultName(_ endpoint: NWEndpoint) -> String? {
    switch endpoint {
    case .service(let name, _, _, _):
        return name
    default:
        return nil
    }
}

private func extractTXTRecord(from result: NWBrowser.Result) -> [String: String] {
    var dict: [String: String] = [:]
    if case .bonjour(let txt) = result.metadata {
        let keys = ["ram", "chip", "status"]
        for key in keys {
            dict[key] = txt[key]
        }
    }
    return dict
}

private func parseInt(_ string: String) -> Int {
    return Int(string.filter { $0.isNumber }) ?? 0
}
