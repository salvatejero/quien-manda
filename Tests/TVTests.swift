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
}
