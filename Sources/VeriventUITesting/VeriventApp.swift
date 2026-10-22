import Foundation
import XCTest

/**
 The app under test, launched with Verivent's test server on, to check its analytics from a UI test
 the way a Kotlin test does with `Baseline.flow`:

 ```swift
 let verivent = try VeriventApp.launch(app)
 try verivent.flow("checkout") { flow in
     try flow.step("browse") { app.buttons["Desk lamp"].tap() }
     try flow.step("pay") {
         app.buttons["Pay"].tap()
         flow.bind("orderId", app.staticTexts["orderId"].label)
     }
 }
 try verivent.lastEvent("purchase", on: "firebase").shouldMatchPlan().shouldHave("currency", "EUR")
 ```

 The app needs nothing but Verivent: launched this way, it starts the server the first time it calls
 Verivent. The test runs no Verivent code; it asks the app over the simulator's loopback.
 */
public final class VeriventApp {

    private let server: Server

    private init(server: Server) {
        self.server = server
    }

    /// Launches `app` with the server on, on `port`, and waits up to `timeout` for it to answer.
    public static func launch(_ app: XCUIApplication, port: Int = 9397, timeout: TimeInterval = 10) throws -> VeriventApp {
        let server = Server(port: port, token: UUID().uuidString)
        app.launchEnvironment["VERIVENT_UITEST_TOKEN"] = server.token
        app.launchEnvironment["VERIVENT_UITEST_PORT"] = String(port)
        app.launch()
        let deadline = Date().addingTimeInterval(timeout)
        while !server.isUp() {
            guard Date() < deadline else {
                throw VeriventUsageError(description: "Verivent didn't answer on port \(port) within \(timeout)s: does the app call Verivent on launch?")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return VeriventApp(server: server)
    }

    /**
     Runs `body` and checks the analytics it sends against the baseline `<name>.json` in `bundle`
     (the test bundle when nil), step by step, waiting up to `timeout` for each step's events.

     With `VERIVENT_RECORD_DIR` in the test's environment (`TEST_RUNNER_VERIVENT_RECORD_DIR=… xcodebuild
     test` sets it), it records instead, and writes `<name>.json` there to polish and commit.

     - Throws: `BaselineMismatch` when a step, or the flow as a whole, doesn't match.
     */
    public func flow(_ name: String, bundle: Bundle? = nil, timeout: TimeInterval = 5, _ body: (VeriventFlow) throws -> Void) throws {
        let recordDir = ProcessInfo.processInfo.environment["VERIVENT_RECORD_DIR"]
        let millis = String(Int(timeout * 1000))
        if recordDir != nil {
            _ = try server.post("/api/baseline/flow", query: ["record": name, "timeout": millis], timeout: timeout + 10)
        } else {
            _ = try server.post("/api/baseline/flow", query: ["timeout": millis], body: try baseline(name, in: bundle), timeout: timeout + 10)
        }
        let flow = VeriventFlow(server: server, timeout: timeout)
        try body(flow)
        let answer = try server.post("/api/baseline/finish", body: flow.variables(), timeout: timeout * 2 + 10)
        try verdict(answer)
        if let recordDir = recordDir, let recording = answer["recording"] as? String {
            let file = URL(fileURLWithPath: recordDir).appendingPathComponent("\(name).json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try recording.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// The latest `name` event on `channel`, waiting up to `timeout` for one, to check on its own.
    public func lastEvent(_ name: String, on channel: String, timeout: TimeInterval = 5) -> VeriventEventCheck {
        VeriventEventCheck(server: server, event: ["name": name, "channel": channel, "timeout": Int(timeout * 1000)], timeout: timeout)
    }

    private func baseline(_ name: String, in bundle: Bundle?) throws -> Data {
        let url = (bundle.map { [$0] } ?? Bundle.allBundles).lazy.compactMap { $0.url(forResource: name, withExtension: "json") }.first
        guard let url = url else { throw VeriventUsageError(description: "\(name).json isn't in the test bundle: record it first") }
        return try Data(contentsOf: url)
    }
}
