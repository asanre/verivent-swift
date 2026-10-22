import Foundation

/// The app's Verivent server, on the simulator's loopback, which the test runner shares. Every call
/// carries the launch's token and the header the server asks of a request that changes something.
struct Server {
    let port: Int
    let token: String

    /// The JSON the server answered with, or the reason it refused.
    func post(_ path: String, query: [String: String] = [:], body: Data? = nil, timeout: TimeInterval) throws -> [String: Any] {
        var request = URLRequest(url: url(path, query: query), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("1", forHTTPHeaderField: "X-Verivent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (status, data) = try send(request)
        guard status == 200 else {
            throw VeriventUsageError(description: String(data: data, encoding: .utf8).map { "\(status): \($0)" } ?? "\(status)")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Whether the server answers yet: it binds once the app first touches Verivent.
    func isUp() -> Bool {
        (try? send(URLRequest(url: url("/api/tracking-plan"), timeoutInterval: 1)).0) == 200
    }

    private func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(string: "http://127.0.0.1:\(port)\(path)")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "t", value: token)]
        return components.url!
    }

    private func send(_ request: URLRequest) throws -> (Int, Data) {
        let done = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error> = .failure(URLError(.timedOut))
        URLSession.shared.dataTask(with: request) { data, response, error in
            result = error.map { .failure($0) } ?? .success(((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data()))
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }
}

/// Verivent refused a call: a step out of the baseline's order, a baseline file it can't read, a
/// flow started on an app `VeriventApp.launch` didn't launch.
public struct VeriventUsageError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public var errorDescription: String? { description }
}

/// The app's analytics don't match: the report names the step, each event and what was expected,
/// as the Kotlin test's `BaselineMismatch` does.
public struct BaselineMismatch: Error, CustomStringConvertible, LocalizedError {
    public let report: String
    public var description: String { report }
    public var errorDescription: String? { report }
}

/// [object] as JSON. Checked first: `JSONSerialization` raises an Objective-C exception, which no
/// Swift `catch` stops, on a value JSON has no type for, a `Date` say.
func json(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw VeriventUsageError(description: "only JSON values can be sent: strings, numbers, booleans, arrays and dictionaries of them, in \(object)")
    }
    return try JSONSerialization.data(withJSONObject: object)
}

/// What a check answered: nothing when it passed, the report when it didn't.
func verdict(_ answer: [String: Any]) throws {
    guard answer["passed"] as? Bool == true else {
        throw BaselineMismatch(report: answer["report"] as? String ?? "failed without a report")
    }
}
