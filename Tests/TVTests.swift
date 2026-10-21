import StoreKitTest
import XCTest
@testable import SonyMando

final class TVTests: XCTestCase {
    func testParseCodes() throws {
        let json = #"[{"bundled":true,"type":"IR_REMOTE_BUNDLE_TYPE_AEP_N"},[{"name":"Num1","value":"AAAAAQAAAAEAAAAAAw=="},{"name":"Up","value":"AAAAAQAAAAEAAAB0Aw=="}]]"#
        let result = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [Any]
        XCTAssertEqual(try TV.parseCodes(result), ["Num1": "AAAAAQAAAAEAAAAAAw==", "Up": "AAAAAQAAAAEAAAB0Aw=="])
        XCTAssertThrowsError(try TV.parseCodes([]))
    }

    func testSoapWrapsCode() {
        XCTAssertTrue(TV.soap("ABC=").contains("<IRCCCode>ABC=</IRCCCode>"))
    }

    func testParseVolumePrefersSpeaker() {
        let result: [Any] = [[["target": "headphone", "volume": 5, "mute": false, "maxVolume": 100],
                              ["target": "speaker", "volume": 24, "mute": true, "maxVolume": 80]]]
        XCTAssertEqual(TV.parseVolume(result), TV.Volume(level: 24, max: 80, muted: true))
        XCTAssertNil(TV.parseVolume([]))
    }

    func testAppURIMatchesTitle() {
        let result: [Any] = [[["title": "YouTube", "uri": "yt"], ["title": "Prime Video", "uri": "pv", "icon": "http://tv/pv.png"]]]
        XCTAssertEqual(TV.app(result, named: "prime video")?["icon"] as? String, "http://tv/pv.png")
        XCTAssertNil(TV.app(result, named: "Plex"))
    }

    func testPanelAppsRoundTrip() {
        let apps = PanelApp.decode(PanelApp.defaults)
        XCTAssertEqual(apps.count, 8)
        XCTAssertEqual(apps[5], PanelApp(name: "Disney+", on: false))
        XCTAssertEqual(PanelApp.encode(apps), PanelApp.defaults)
    }

    func testPanelMergesWithTVApps() {
        let stored = [PanelApp(name: "Netflix", on: true), PanelApp(name: "HBO", on: true), PanelApp(name: "Plex", on: true)]
        let merged = PanelApp.merge(stored, titles: ["YouTube", "HBO Max", "Netflix"])
        XCTAssertEqual(merged, [PanelApp(name: "Netflix", on: true), PanelApp(name: "HBO Max", on: true), PanelApp(name: "YouTube", on: false)])
        XCTAssertEqual(PanelApp.merge(stored, titles: []), stored)
    }

    func testAuthCookieFromSetCookie() {
        let url = URL(string: "http://192.0.2.20/sony/accessControl")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Set-Cookie": "auth=abc123; Path=/sony/; Max-Age=1209600"])!
        XCTAssertEqual(TV.authCookie(response), "abc123")
    }

    func testKeychainRoundTrip() {
        Keychain.save("abc", "test-ip")
        XCTAssertEqual(Keychain.load("test-ip"), "abc")
        Keychain.save(nil, "test-ip")
        XCTAssertNil(Keychain.load("test-ip"))
    }

    /// Los tres cafés existen en la configuración local y se pueden comprar (y repetir: son consumibles).
    @MainActor
    func testCoffeeProducts() async throws {
        let session = try SKTestSession(configurationFileNamed: "Cafe")
        session.disableDialogs = true
        session.clearTransactions()
        let products = try await Product.products(for: Coffee.ids)
        XCTAssertEqual(Set(products.map(\.id)), Set(Coffee.ids))
        XCTAssertTrue(products.allSatisfy { $0.type == .consumable })
        let coffee = try XCTUnwrap(products.first { $0.id == Coffee.ids[0] })
        for _ in 0..<2 {
            guard case .success(.verified(let transaction)) = try await coffee.purchase() else { return XCTFail("compra fallida") }
            await transaction.finish()
        }
    }

    /// Un icono descargado una vez sale del disco aunque la TV ya no esté (ni la memoria).
    @MainActor
    func testIconDiskCache() async throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "icono-prueba.png")
        try XCTUnwrap(UIImage(systemName: "tv")?.pngData()).write(to: source)
        try? FileManager.default.removeItem(at: Monogram.folder.appending(path: source.lastPathComponent))
        let downloaded = await Monogram.load(source)
        XCTAssertNotNil(downloaded)
        try FileManager.default.removeItem(at: source)
        Monogram.memory = [:]
        let fromDisk = await Monogram.load(source)
        XCTAssertNotNil(fromDisk)
    }

    /// Pasado el mes se vuelve a bajar; si la TV no responde, vale el icono caducado.
    @MainActor
    func testIconCacheExpires() async throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "icono-caduca.png")
        let cached = Monogram.folder.appending(path: source.lastPathComponent)
        try XCTUnwrap(UIImage(systemName: "tv")?.pngData()).write(to: source)
        try? FileManager.default.removeItem(at: cached)
        _ = await Monogram.load(source)

        let old = Date.now.addingTimeInterval(-Monogram.maxAge - 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: cached.path)
        let newIcon = try XCTUnwrap(UIImage(systemName: "star")?.pngData())
        try newIcon.write(to: source)
        Monogram.memory = [:]
        _ = await Monogram.load(source)
        XCTAssertEqual(try Data(contentsOf: cached), newIcon)

        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: cached.path)
        try FileManager.default.removeItem(at: source)
        Monogram.memory = [:]
        let stale = await Monogram.load(source)
        XCTAssertNotNil(stale)
    }
}
