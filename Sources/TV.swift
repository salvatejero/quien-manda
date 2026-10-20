import Foundation

/// Cliente BRAVIA: JSON-RPC (/sony/*) + teclas IRCC por SOAP.
/// Auth: PSK (cabecera X-Auth-PSK) o PIN (actRegister → cookie "auth", que URLSession guarda sola).
@MainActor @Observable
final class TV {
    enum Failure: LocalizedError {
        case needsPin, http(Int), unknownKey(String), badResponse
        var errorDescription: String? {
            switch self {
            case .needsPin: "Introduce el PIN que aparece en la TV"
            case .http(let code): "La TV respondió \(code)"
            case .unknownKey(let name): "Tecla no disponible: \(name)"
            case .badResponse: "Respuesta inesperada de la TV"
            }
        }
    }

    var ip = ""
    var psk = ""
    private(set) var codes: [String: String] = [:]

    var isConnected: Bool { !codes.isEmpty }

    /// Con PSK basta con leer los códigos; sin PSK hace falta registrarse (la 1ª vez sin PIN, la TV lo muestra).
    func connect(pin: String? = nil) async throws {
        if psk.isEmpty { try await register(pin: pin) }
        let result = try await call("system", "getRemoteControllerInfo")
        codes = try Self.parseCodes(result)
    }

    func disconnect() { codes = [:] }

    func press(_ name: String) async throws {
        guard let code = codes[name] else { throw Failure.unknownKey(name) }
        var request = request("ircc")
        request.setValue("\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.soap(code).data(using: .utf8)
        try await send(request)
    }

    /// IRCC no despierta la TV en standby; setPowerStatus sí.
    func togglePower() async throws {
        let status = try await call("system", "getPowerStatus")
        let active = ((status.first as? [String: Any])?["status"] as? String) == "active"
        _ = try await call("system", "setPowerStatus", params: [["status": !active]])
    }

    // MARK: - Red

    private func register(pin: String?) async throws {
        let params: [Any] = [
            ["clientid": "sonymando:\(Self.clientID)", "nickname": "Mando TV", "level": "private"],
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
