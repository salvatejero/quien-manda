import Foundation
import Network
import os

struct FoundTV: Identifiable, Hashable {
    let ip: String
    let name: String
    var id: String { ip }
}

/// Busca TVs BRAVIA sin el entitlement de multicast:
/// 1. Bonjour `_googlecast._tcp` (las BRAVIA Android/Google TV lo anuncian).
/// 2. Barrido de la subred local preguntando `getInterfaceInformation` (no pide auth).
/// Toda IP candidata se confirma con esa misma llamada, así que un Chromecast que no sea BRAVIA no aparece.
@MainActor @Observable
final class Discovery {
    private(set) var tvs: [FoundTV] = []
    private(set) var isScanning = false
    private var browser: NWBrowser?

    func start() {
        stop()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                let name: String? = if case .bonjour(let txt) = result.metadata { txt["fn"] } else { nil }
                Task { @MainActor in
                    guard let ip = await Self.resolve(result.endpoint) else { return }
                    await self?.add(ip: ip, name: name)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        Task { await scanSubnet() }
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private func scanSubnet() async {
        guard !isScanning, let (ip, mask) = Self.localIPv4() else { return }
        isScanning = true
        defer { isScanning = false }
        await withTaskGroup(of: Void.self) { group in
            for host in Self.hosts(ip: ip, mask: mask) {
                group.addTask { await self.add(ip: Self.format(host), name: nil) }
            }
        }
    }

    /// Si llega por Bonjour, su nombre ("fn", el que el usuario puso a la TV) gana al modelo.
    private func add(ip: String, name: String?) async {
        guard let model = await Self.probe(ip) else { return }
        let tv = FoundTV(ip: ip, name: name ?? model)
        if let i = tvs.firstIndex(where: { $0.ip == ip }) {
            if name != nil { tvs[i] = tv }
        } else {
            tvs.append(tv)
        }
    }

    // MARK: - Red

    nonisolated private static func probe(_ ip: String) async -> String? {
        var request = URLRequest(url: URL(string: "http://\(ip)/sony/system")!, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"method":"getInterfaceInformation","params":[],"id":1,"version":"1.0"}"#.utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return modelName(data)
    }

    /// Un servicio Bonjour no trae IP: se abre una conexión TCP (solo IPv4) y se lee el extremo remoto.
    nonisolated private static func resolve(_ endpoint: NWEndpoint) async -> String? {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        let done = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ ip: String?) {
                guard done.withLock({ was in defer { was = true }; return !was }) else { return }
                connection.cancel()
                continuation.resume(returning: ip)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(.ipv4(let address), _) = connection.currentPath?.remoteEndpoint {
                        finish("\(address)".components(separatedBy: "%")[0]) // quita el "%en0"
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }

    /// IPv4 y máscara de la Wi-Fi (en0), en orden de host.
    nonisolated private static func localIPv4() -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = ifa.pointee
            guard String(cString: i.ifa_name) == "en0", i.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
                  let addr = i.ifa_addr, let mask = i.ifa_netmask else { continue }
            let value = { (p: UnsafeMutablePointer<sockaddr>) in
                p.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            return (value(addr), value(mask))
        }
        return nil
    }

    // MARK: - Lógica pura (probada en Tests/)

    /// Hosts de la subred, sin red, broadcast ni la IP propia.
    nonisolated static func hosts(ip: UInt32, mask: UInt32) -> [UInt32] {
        let mask = max(mask, 0xFFFF_FF00) // ponytail: subred mayor que /24 → solo el /24 propio; ampliar si hay redes /16 reales
        let network = ip & mask
        return (1..<(~mask)).map { network | $0 }.filter { $0 != ip }
    }

    nonisolated static func format(_ ip: UInt32) -> String {
        [24, 16, 8, 0].map { String((ip >> $0) & 0xFF) }.joined(separator: ".")
    }

    /// `result = [{productCategory:"tv", modelName:"KD-55XF9005", ...}]`. Solo cuenta si es una TV.
    nonisolated static func modelName(_ data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let info = (json?["result"] as? [Any])?.first as? [String: Any],
              info["productCategory"] as? String == "tv" else { return nil }
        return info["modelName"] as? String ?? "BRAVIA"
    }
}
