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
}
