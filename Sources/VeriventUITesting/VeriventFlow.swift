import Foundation

/// The body of `VeriventApp.flow`: the test's own actions, optionally split into steps.
public final class VeriventFlow {

    private let server: Server
    private let timeout: TimeInterval
    private var bound: [String: Any] = [:]

    init(server: Server, timeout: TimeInterval) {
        self.server = server
        self.timeout = timeout
    }

    /// The values bound so far, as the server takes them.
    func variables() throws -> Data { try json(["variables": bound]) }

    /**
     Runs `action` as the baseline's next step, then waits until the events it sent match the step
     (or, recording, until they stop arriving).

     - Throws: `BaselineMismatch` when they still don't match once the timeout runs out, and
       `VeriventUsageError` when the baseline has no such step next.
     */
    public func step(_ name: String, _ action: () throws -> Void) throws {
        _ = try server.post("/api/baseline/step", query: ["name": name], timeout: timeout + 10)
        try action()
        try verdict(server.post("/api/baseline/step/end", body: variables(), timeout: timeout + 10))
    }

    /// A value the test knows only as it runs: `name` stands for `{{name}}` in the baseline. Recording
    /// writes `{{name}}` wherever the value was sent; comparing fills it in. Bind it before the step
    /// that sends it ends.
    public func bind(_ name: String, _ value: Any) {
        bound[name] = value
    }
}
