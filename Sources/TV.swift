import Foundation

/// Cliente BRAVIA: JSON-RPC (/sony/*) + teclas IRCC por SOAP.
/// Auth: PSK (cabecera X-Auth-PSK) o PIN (actRegister → cookie "auth", que URLSession guarda sola).
@MainActor @Observable
final class TV {
    enum Failure: LocalizedError {
        case needsPin, badPSK, http(Int), unknownKey(String), noApp(String), badResponse
        var errorDescription: String? {
            switch self {
            case .needsPin: "Introduce el PIN que aparece en la TV"
            case .badPSK: "La TV no acepta esa Pre-Shared Key. Déjala vacía para usar el PIN."
            case .http(let code): "La TV respondió \(code)"
            case .unknownKey(let name): "Tecla no disponible: \(name)"
            case .noApp(let name): "La tele no tiene \(name)"
            case .badResponse: "Respuesta inesperada de la TV"
            }
        }
    }

    var ip = ""
    var psk = ""
    private(set) var codes: [String: String] = [:]
    private(set) var model = ""
    private(set) var isOn = true
    private(set) var apps: [Any]?
    /// Modo demo (`-screen` al lanzar): finge una TV con todas las teclas y no toca la red.
    var demo = false { didSet { if demo { model = "KD-55XH8096" } } }

    var isConnected: Bool { !codes.isEmpty }

    /// Con PSK basta con leer los códigos; sin PSK hace falta registrarse (la 1ª vez sin PIN, la TV lo muestra).
    func connect(pin: String? = nil) async throws {
        if psk.isEmpty { try await register(pin: pin) }
        // getRemoteControllerInfo responde sin autenticar; esto no, así que confirma que la TV aceptará las teclas.
        let info: [Any]
        do { info = try await call("system", "getSystemInformation") }
        catch Failure.http(401), Failure.http(403) { throw psk.isEmpty ? Failure.needsPin : Failure.badPSK }
        model = (info.first as? [String: Any])?["model"] as? String ?? "BRAVIA"
        isOn = (try? await powerIsActive()) ?? true
        apps = nil
        let result = try await call("system", "getRemoteControllerInfo")
        codes = try Self.parseCodes(result)
    }

    /// Cada modelo trae sus teclas: la primera de `names` que tenga la TV.
    func has(_ names: [String]) -> Bool { demo || names.contains { codes[$0] != nil } }

    func press(_ names: [String]) async throws {
        if demo { return }
        guard let code = names.lazy.compactMap({ self.codes[$0] }).first else { throw Failure.unknownKey(names[0]) }
        var request = request("ircc")
        request.setValue("\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.soap(code).data(using: .utf8)
        try await send(request)
    }

    /// IRCC no despierta la TV en standby; setPowerStatus sí.
    func togglePower() async throws {
        let active = try await powerIsActive()
        _ = try await call("system", "setPowerStatus", params: [["status": !active]])
        isOn = !active
    }

    func volume() async throws -> Volume {
        if demo { return Volume(level: 24, max: 100, muted: false) }
        guard let volume = Self.parseVolume(try await call("audio", "getVolumeInformation")) else { throw Failure.badResponse }
        return volume
    }

    /// Abre la app cuyo título contiene `name` (la lista se pide una vez por conexión).
    func openApp(_ name: String) async throws {
        try await loadApps()
        guard let uri = Self.app(apps ?? [], named: name)?["uri"] as? String else { throw Failure.noApp(name) }
        _ = try await call("appControl", "setActiveApp", params: [["uri": uri]])
    }

    func loadApps() async throws {
        if apps == nil && !demo { apps = try await call("appControl", "getApplicationList") }
    }

    var appTitles: [String] { (apps?.first as? [[String: Any]] ?? []).compactMap { $0["title"] as? String } }

    /// Icono que da la propia TV para la app (así no se empaquetan logos de terceros).
    func icon(_ name: String) -> URL? {
        (Self.app(apps ?? [], named: name)?["icon"] as? String).flatMap(URL.init(string:))
    }

    private func powerIsActive() async throws -> Bool {
        let status = try await call("system", "getPowerStatus")
        return ((status.first as? [String: Any])?["status"] as? String) == "active"
    }

    // MARK: - Red

    private func register(pin: String?) async throws {
        let params: [Any] = [
            ["clientid": "sonymando:\(Self.clientID)", "nickname": "Quién Manda", "level": "private"],
            [["value": "yes", "function": "WOL"]],
        ]
        var extra: [String: String] = [:]
        if let pin { extra["Authorization"] = "Basic " + Data(":\(pin)".utf8).base64EncodedString() }
        do {
            _ = try await call("accessControl", "actRegister", params: params, headers: extra)
        } catch Failure.http(401) {
            throw Failure.needsPin
        }
    }

    private func call(_ service: String, _ method: String, params: [Any] = [], headers: [String: String] = [:]) async throws -> [Any] {
        var request = request(service)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["method": method, "params": params, "id": 1, "version": "1.0"])
        let data = try await send(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [Any], let code = error.first as? Int { throw Failure.http(code) }
        return json?["result"] as? [Any] ?? []
    }

    private func request(_ service: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://\(ip)/sony/\(service)")!, timeoutInterval: 5)
        request.httpMethod = "POST"
        if !psk.isEmpty { request.setValue(psk, forHTTPHeaderField: "X-Auth-PSK") }
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request, delegate: NoAuthRetry()) }
        catch URLError.cancelled { throw Failure.http(401) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        return data
    }

    // MARK: - Formato (estático para poder probarlo sin TV)

    /// result = [{bundled,type}, [{name, value}, ...]]
    nonisolated static func parseCodes(_ result: [Any]) throws -> [String: String] {
        guard let list = result.last as? [[String: String]] else { throw Failure.badResponse }
        return Dictionary(list.compactMap { item in item["name"].flatMap { n in item["value"].map { (n, $0) } } },
                          uniquingKeysWith: { first, _ in first })
    }

    struct Volume: Equatable { var level: Int, max: Int, muted: Bool }

    /// result = [[{target:"speaker", volume, mute, maxVolume}, {target:"headphone", ...}]]
    nonisolated static func parseVolume(_ result: [Any]) -> Volume? {
        let list = result.first as? [[String: Any]] ?? []
        guard let v = list.first(where: { $0["target"] as? String == "speaker" }) ?? list.first,
              let level = v["volume"] as? Int else { return nil }
        return Volume(level: level, max: v["maxVolume"] as? Int ?? 100, muted: v["mute"] as? Bool ?? false)
    }

    /// result = [[{title, uri, icon}]]
    nonisolated static func app(_ result: [Any], named name: String) -> [String: Any]? {
        let list = result.first as? [[String: Any]] ?? []
        return list.first { ($0["title"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }
            ?? list.first { ($0["title"] as? String)?.localizedCaseInsensitiveContains(name) == true }
    }

    nonisolated static func soap(_ code: String) -> String {
        """
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1"><IRCCCode>\(code)</IRCCCode></u:X_SendIRCC></s:Body></s:Envelope>
        """
    }

    private static let clientID: String = {
        if let id = UserDefaults.standard.string(forKey: "clientID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "clientID")
        return id
    }()
}

/// La TV contesta 401 con "WWW-Authenticate: Basic" y URLSession repite la petición por su cuenta.
/// Un segundo actRegister cierra el PIN en la TV ("Registro cancelado"), así que se corta el reto.
private final class NoAuthRetry: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.cancelAuthenticationChallenge, nil)
    }
}
