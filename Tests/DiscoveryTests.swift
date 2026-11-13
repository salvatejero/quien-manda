import XCTest
@testable import QuienManda

final class DiscoveryTests: XCTestCase {
    func testHostsOfSlash24() {
        let ip: UInt32 = 0xC000_0214 // 192.0.2.20
        let hosts = Discovery.hosts(ip: ip, mask: 0xFFFF_FF00)
        XCTAssertEqual(hosts.count, 253) // .1 … .254 sin la propia
        XCTAssertEqual(Discovery.format(hosts.first!), "192.0.2.1")
        XCTAssertEqual(Discovery.format(hosts.last!), "192.0.2.254")
        XCTAssertFalse(hosts.contains(ip))
    }

    func testWideSubnetIsCappedToOwnSlash24() {
        let hosts = Discovery.hosts(ip: 0xC633_6405, mask: 0xFFFF_0000) // 198.51.100.5/16
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(Discovery.format(hosts.first!), "198.51.100.1")
    }

    func testModelNameOnlyForTVs() {
        let tv = #"{"result":[{"productCategory":"tv","productName":"BRAVIA","modelName":"KD-55XF9005"}],"id":1}"#
        let other = #"{"result":[{"productCategory":"audio","modelName":"HT-X"}],"id":1}"#
        XCTAssertEqual(Discovery.modelName(Data(tv.utf8)), "KD-55XF9005")
        XCTAssertNil(Discovery.modelName(Data(other.utf8)))
        XCTAssertNil(Discovery.modelName(Data("<html>".utf8)))
    }
}
