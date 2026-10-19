import Foundation

/**
 The session that actually performs the intercepted requests, and the delegate that reports them
 back to their `VeriventURLProtocol`.

 One shared session rather than one per request: a session per call throws away connection pooling,
 so every request would pay for a fresh TLS handshake — a steep price for a debug tool. Its
 configuration is a copy of the host's, minus our own protocol class, so timeouts, cookies, extra
 headers, the TLS minimum and the cache policy all survive interception.
 */
final class InnerSession: NSObject {

    static let shared = InnerSession()

    private let lock = NSLock()
    private var handlers: [Int: VeriventURLProtocol] = [:]
    private var configuration = URLSessionConfiguration.default
    private var cached: URLSession?

    private lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        // Serial, so a task's callbacks never interleave with each other.
        queue.maxConcurrentOperationCount = 1
        queue.name = "io.github.asanre.verivent.inner-session"
        return queue
    }()

    var session: URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cached { return cached }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        cached = session
        return session
    }

    /// Adopt the host's configuration for the requests we replay. A second install replaces the
    /// first — last one wins, which is why `installNetworkInterceptor(on:)` documents it.
    func adopt(_ hostConfiguration: URLSessionConfiguration) {
        guard let copy = hostConfiguration.copy() as? URLSessionConfiguration else { return }
        copy.protocolClasses = (copy.protocolClasses ?? []).filter { $0 != VeriventURLProtocol.self }
        lock.lock()
        configuration = copy
        let previous = cached
        cached = nil
        lock.unlock()
        previous?.finishTasksAndInvalidate()
    }

    func register(_ handler: VeriventURLProtocol, for task: URLSessionTask) {
        lock.lock()
        handlers[task.taskIdentifier] = handler
        lock.unlock()
    }

    func forget(_ taskIdentifier: Int) {
        lock.lock()
        handlers.removeValue(forKey: taskIdentifier)
        lock.unlock()
    }

    private func handler(for task: URLSessionTask) -> VeriventURLProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[task.taskIdentifier]
    }
}

extension InnerSession: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            handler(for: dataTask)?.received(response: http)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(for: dataTask)?.received(data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let handler = handler(for: task)
        forget(task.taskIdentifier)
        handler?.completed(error: error)
    }

    /// Fired before `didCompleteWithError`, which is what makes the negotiated protocol available
    /// in time to be recorded with the response.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let name = metrics.transactionMetrics.last?.networkProtocolName else { return }
        handler(for: task)?.negotiated(protocolName: name)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        handler(for: task)?.redirecting(to: request, response: response)
        // nil: the inner session must not follow it. The loading system re-issues the redirect,
        // which gives the hop its own entry and lets the host's own delegate see it.
        completionHandler(nil)
    }

    /**
     Default handling, which is the honest limitation of this approach: the host's own
     `URLSessionDelegate` is not consulted for an intercepted request, so certificate pinning or a
     credential it would have supplied never runs. Documented on `installNetworkInterceptor(on:)`;
     the escape hatch is not installing on that configuration.
     */
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}
