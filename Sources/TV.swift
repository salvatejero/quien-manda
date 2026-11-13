import Foundation
import Security
import os

/// Fallos de red con la TV, para leerlos en Consola.app (filtro: categoría "tv").
private let log = Logger(subsystem: "QuienManda", category: "tv")

/// Cliente BRAVIA: JSON-RPC (/sony/*) + teclas IRCC por SOAP.
/// Auth: PSK (cabecera X-Auth-PSK) o PIN (actRegister → cookie "auth", que URLSession guarda sola).
@MainActor @Observable
final class TV {
    enum Failure: LocalizedError {
        case needsPin, badPSK, http(Int), unknownKey(String), noApp(String), badResponse
        var errorDescription: String? {
            switch self {
            case .needsPin: String(localized: "Introduce el PIN que aparece en la TV")
            case .badPSK: String(localized: "La TV no acepta esa Pre-Shared Key. Déjala vacía para usar el PIN.")
            case .http(let code): Self.text(code)
            case .unknownKey(let name): String(localized: "Tecla no disponible: \(name)")
            case .noApp(let name): String(localized: "La tele no tiene \(name)")
            case .badResponse: String(localized: "Respuesta inesperada de la TV")
            }
        }

        /// Códigos HTTP y de error JSON-RPC de BRAVIA, dichos para personas. El código solo sale si no lo conocemos.
        static func text(_ code: Int) -> String {
            switch code {
            case 0: String(localized: "La tele no responde. ¿Está encendida y en la misma wifi?")
            case 401, 403: String(localized: "La tele no te deja controlarla. Vuelve a vincularla con el PIN.")
            case 404, 501, 12, 14, 15: String(localized: "Tu tele no admite esta orden.")
            case 2, 503, 40000: String(localized: "La tele está ocupada. Prueba otra vez en un momento.")
            case 3, 5, 7: String(localized: "La tele no puede hacer eso ahora mismo.")
            case 40005: String(localized: "La pantalla de la tele está apagada. Enciéndela y vuelve a probar.")
            default: String(localized: "La tele no ha podido hacerlo (error \(String(code))).")
            }
        }
    }

    var ip = ""
    var psk = ""
    private(set) var codes: [String: String] = [:]
    private(set) var model = ""
    private(set) var isOn = true
    private(set) var apps: [Any]?
    /// Cookie "auth" del registro por PIN. Va en el llavero (por IP) y se envía a mano.
    private var auth: String?
    /// Modo demo ("Probar sin tele" o `-screen` al lanzar): finge una TV con todas las teclas y no toca la red.
    var demo = false { didSet { if demo { model = "KD-55XH8096" } } }

    var isConnected: Bool { !codes.isEmpty }

    /// Con PSK basta con leer los códigos. Sin PSK: si hay cookie guardada se usa tal cual (directo al mando);
    /// si no la hay, o caducó, se registra (sin PIN la TV lo muestra; con PIN guarda la cookie nueva).
    func connect(pin: String? = nil) async throws {
        auth = psk.isEmpty ? Keychain.load(ip) : nil
        if psk.isEmpty && (auth == nil || pin != nil) { try await register(pin: pin) }
        // getRemoteControllerInfo responde sin autenticar; esto no, así que confirma que la TV aceptará las teclas.
        let info: [Any]
        do { info = try await call("system", "getSystemInformation") }
        catch Failure.http(401), Failure.http(403) {
            guard psk.isEmpty else { throw Failure.badPSK }
            // Cookie caducada: se pide otra (la TV mostrará un PIN si ya no reconoce al cliente).
            Keychain.save(nil, ip)
            auth = nil
            try await register(pin: nil)
            info = try await call("system", "getSystemInformation")
        }
        model = (info.first as? [String: Any])?["model"] as? String ?? "BRAVIA"
        isOn = (try? await powerIsActive()) ?? true
        apps = nil
        let result = try await call("system", "getRemoteControllerInfo")
        codes = try Self.parseCodes(result)
    }

    /// Cada modelo trae sus teclas: la primera de `names` que tenga la TV.
    func has(_ names: [String]) -> Bool { demo || names.contains { codes[$0] != nil } }

    func press(_ names: [String]) async throws {
        if demo {
            let fail = UserDefaults.standard.integer(forKey: "fail") // `-fail 40005` para ver el toast de error
            if fail != 0 { throw Failure.http(fail) }
            return
        }
        guard let code = names.lazy.compactMap({ self.codes[$0] }).first else { throw Failure.unknownKey(names[0]) }
        var request = request("ircc")
        request.setValue("\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.soap(code).data(using: .utf8)
        try await send(request)
    }

    /// IRCC no despierta la TV en standby; setPowerStatus sí.
    func togglePower() async throws {
        if demo { isOn.toggle(); return }
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
        if demo { return }
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
        let response: HTTPURLResponse
        do {
            (_, response) = try await rpc("accessControl", "actRegister", params: params, headers: extra)
        } catch Failure.http(401) {
            throw Failure.needsPin
        }
        if let cookie = Self.authCookie(response) {
            auth = cookie
            Keychain.save(cookie, ip)
        }
    }

    private func call(_ service: String, _ method: String, params: [Any] = []) async throws -> [Any] {
        try await rpc(service, method, params: params).result
    }

    private func rpc(_ service: String, _ method: String, params: [Any] = [], headers: [String: String] = [:]) async throws -> (result: [Any], response: HTTPURLResponse) {
        var request = request(service)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["method": method, "params": params, "id": 1, "version": "1.0"])
        let (data, response) = try await send(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [Any], let code = error.first as? Int {
            log.error("\(service, privacy: .public).\(method, privacy: .public) → error \(code) \(String(describing: error), privacy: .public)")
            throw Failure.http(code)
        }
        return (json?["result"] as? [Any] ?? [], response)
    }

    private func request(_ service: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://\(ip)/sony/\(service)")!, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false // la cookie la gestionamos nosotros (llavero)
        if !psk.isEmpty { request.setValue(psk, forHTTPHeaderField: "X-Auth-PSK") }
        if let auth { request.setValue("auth=\(auth)", forHTTPHeaderField: "Cookie") }
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request, delegate: NoAuthRetry()) }
        catch URLError.networkConnectionLost {
            // Tras un rato en segundo plano la TV ya ha cerrado el keep-alive y la primera petición muere con -1005.
            // URLSession no reintenta POST, así que se repite una vez por una conexión nueva.
            log.notice("\(request.url?.path ?? "", privacy: .public) → -1005, reintento")
            do { (data, response) = try await URLSession.shared.data(for: request, delegate: NoAuthRetry()) }
            catch { throw Failure.http((error as? URLError)?.code == .cancelled ? 401 : 0) }
        }
        catch URLError.cancelled { throw Failure.http(401) }
        catch let error as URLError { // timeout, sin red, IP que no existe…
            log.error("\(request.url?.path ?? "", privacy: .public) → URLError \(error.code.rawValue)")
            throw Failure.http(0)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            log.error("\(request.url?.path ?? "", privacy: .public) → HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) \(String(decoding: data.prefix(300), as: UTF8.self), privacy: .public)")
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return (data, http)
    }

    // MARK: - Formato (estático para poder probarlo sin TV)

    /// result = [{bundled,type}, [{name, value}, ...]]
    nonisolated static func parseCodes(_ result: [Any]) throws -> [String: String] {
        guard let list = result.last as? [[String: String]] else { throw Failure.badResponse }
        return Dictionary(list.compactMap { item in item["name"].flatMap { n in item["value"].map { (n, $0) } } },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Valor de la cookie "auth" que devuelve actRegister en Set-Cookie.
    nonisolated static func authCookie(_ response: HTTPURLResponse) -> String? {
        guard let url = response.url, let fields = response.allHeaderFields as? [String: String] else { return nil }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).first { $0.name == "auth" }?.value
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

/// Llavero mínimo: una cadena por cuenta (la IP de la TV).
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "tv-auth", kSecAttrAccount as String: account]
    }

    static func load(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `nil` borra.
    static func save(_ value: String?, _ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
