import Foundation

/// Checks on the latest event of a name and channel, chained; each throws `BaselineMismatch` naming
/// what was expected.
public struct VeriventEventCheck {

    let server: Server
    let event: [String: Any]
    let timeout: TimeInterval

    /// The tracking plan loaded in the app now checked this event and found nothing wrong.
    @discardableResult
    public func shouldMatchPlan() throws -> VeriventEventCheck {
        try check(["plan": true])
    }

    /// `property` was sent with `value`, compared as JSON (`3` equals `3.0`, not `"3"`). A redacted
    /// property can't be checked: only its type is known.
    @discardableResult
    public func shouldHave(_ property: String, _ value: Any) throws -> VeriventEventCheck {
        try check(["property": property, "value": value])
    }

    private func check(_ what: [String: Any]) throws -> VeriventEventCheck {
        try verdict(server.post("/api/baseline/last", body: json(event.merging(what) { $1 }), timeout: timeout + 10))
        return self
    }
}
