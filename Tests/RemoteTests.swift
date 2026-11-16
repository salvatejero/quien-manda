import XCTest
@testable import QuienManda

@MainActor
final class RemoteTests: XCTestCase {
    func testQueueRunsInOrder() async {
        let queue = CommandQueue()
        var done: [Int] = []
        let finished = expectation(description: "todas")
        for n in 0..<10 {
            queue.enqueue {
                // las primeras tardan más: sin cola acabarían en otro orden
                try? await Task.sleep(for: .milliseconds(10 * (10 - n)))
                done.append(n)
                if n == 9 { finished.fulfill() }
            }
        }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(done, Array(0..<10))
    }

    func testCoalescingDropsRepeatsWhileBusy() async {
        let queue = CommandQueue()
        var done: [String] = []
        let finished = expectation(description: "fin")
        queue.enqueue(coalescing: true) { try? await Task.sleep(for: .milliseconds(50)); done.append("a") }
        queue.enqueue(coalescing: true) { done.append("repetida") } // en vuelo → se descarta
        queue.enqueue { done.append("b"); finished.fulfill() }    // una orden normal nunca se descarta
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(done, ["a", "b"])
        queue.enqueue(coalescing: true) { done.append("c") }      // cola libre → pasa
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(done.last, "c")
    }

    func testHdmiPort() {
        XCTAssertEqual(TV.hdmiPort(from: "extInput:hdmi?port=4"), 4)
        XCTAssertNil(TV.hdmiPort(from: "tv:dvbt"))
        XCTAssertEqual(TV.inputKey(from: "extInput:hdmi?port=2"), "Hdmi2")
        XCTAssertEqual(TV.inputKey(from: "tv:dvbt"), "Tv")
        XCTAssertEqual(TV.inputKey(from: "com.sony.dtv.com.netflix"), "")
    }
}
