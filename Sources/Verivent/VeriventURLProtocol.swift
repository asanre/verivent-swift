import Foundation
import VeriventKit

/**
 Intercepts every HTTP call made through a `URLSessionConfiguration` it was installed on and feeds
 it to Verivent. Install it with `Verivent.installNetworkInterceptor(on:)` rather than reaching for this
 class directly; it is public only so a host can recognise or remove it in its own
 `protocolClasses`.

 **Experimental** — the shape of this may change in a minor release.
 */
public final class VeriventURLProtocol: URLProtocol {

    /// Marks a request we already handled, so the copy we send through the inner session doesn't
    /// come straight back to us. The scheme check below can't do this on its own.
    private static let handledKey = "io.github.asanre.verivent.handled"

    /// A request body stream is one-shot: reading a prefix and handing the rest back is impossible,
    /// so a body is only captured when we can drain it whole and re-attach it. Past this size the
    /// upload's integrity wins over seeing it.
    private static let streamDrainCap: Int64 = 1 << 20

    /// Where a finished call is recorded: the host's body sanitizer and the copy into Kotlin run
    /// here, not on the delegate queue every intercepted request shares. Serial, so a call's record
    /// keeps its order.
    private static let captureQueue = DispatchQueue(label: "io.github.asanre.verivent.capture")

    private let lock = NSLock()
    private var callId: String?
    private var innerTask: URLSessionTask?
    private var startedAt: DispatchTime?
    private var httpResponse: HTTPURLResponse?
    private var protocolName: String?
    private var buffered = Data()
    private var totalResponseBytes: Int64 = 0
    /// Bytes of the response worth keeping, read once: every chunk checks it.
    private var responseCap = 0
    private var finished = false
    private var stopped = false

    // MARK: - URLProtocol

    public override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let marked = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        VeriventURLProtocol.setProperty(true, forKey: VeriventURLProtocol.handledKey, in: marked)
        var inner = marked as URLRequest

        let body: RequestBody
        do {
            body = try VeriventURLProtocol.captureRequestBody(from: request, into: &inner)
        } catch {
            // The stream is spent by now: sending what's left would upload a truncated body.
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let url = request.url

        let id = NativeNetwork.shared.begin(
            method: request.httpMethod ?? "GET",
            url: url?.absoluteString ?? "",
            host: url?.host ?? "",
            path: url?.path ?? "",
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            headers: request.allHTTPHeaderFields ?? [:],
            body: body.data,
            bodyByteCount: body.byteCount,
            bodyPlaceholder: body.placeholder
        )

        let task = InnerSession.shared.session.dataTask(with: inner)
        lock.lock()
        callId = id
        innerTask = task
        startedAt = DispatchTime.now()
        // One byte past the limit is all Kotlin needs to flag truncation, exactly like the Ktor
        // adapter's `readRemaining(maxLen + 1)`.
        responseCap = Int(NativeNetwork.shared.maxContentLength) + 1
        lock.unlock()

        InnerSession.shared.register(self, for: task)
        task.resume()
    }

    public override func stopLoading() {
        lock.lock()
        let alreadyDone = finished
        finished = true
        stopped = true
        let id = callId
        let elapsed = elapsedMillisLocked()
        let task = innerTask
        lock.unlock()

        task?.cancel()
        if !alreadyDone, let id = id {
            NativeNetwork.shared.fail(id: id, message: "cancelled", durationMillis: elapsed)
        }
        if let identifier = task?.taskIdentifier {
            InnerSession.shared.forget(identifier)
        }
    }

    // MARK: - Driven by the inner session's delegate

    func received(response: HTTPURLResponse) {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        httpResponse = response
        lock.unlock()
        // The inner session already applied the request's cache policy; letting the outer client
        // cache a second copy would only duplicate it.
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func received(data: Data) {
        lock.lock()
        let gone = stopped
        lock.unlock()
        // Cancelling the inner task is not instant, so a chunk can still arrive after the client
        // let go. Talking to it then is a use-after-teardown.
        guard !gone else { return }

        // Forwarded first and unmodified: the host's streaming must never wait on Verivent.
        client?.urlProtocol(self, didLoad: data)

        lock.lock()
        defer { lock.unlock() }
        totalResponseBytes += Int64(data.count)
        if buffered.count < responseCap {
            buffered.append(data.prefix(responseCap - buffered.count))
        }
    }

    /**
     The ALPN name URLSession negotiated (`http/1.1`, `h2`, `h3`), which is the only place Foundation
     exposes it — `HTTPURLResponse` has no HTTP-version property. Stored as reported rather than
     reshaped into Ktor's `HTTP/2.0` spelling: those are the names the protocol registry uses.

     Metrics only arrive as the task finishes, so a redirect hop — which is closed and cancelled
     before then — keeps an empty protocol.
     */
    func negotiated(protocolName: String) {
        lock.lock()
        self.protocolName = protocolName
        lock.unlock()
    }

    func completed(error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let id = callId
        let elapsed = elapsedMillisLocked()
        let response = httpResponse
        let body = buffered
        let total = totalResponseBytes
        let silent = stopped
        let negotiated = protocolName
        lock.unlock()

        if let error = error {
            if !silent { client?.urlProtocol(self, didFailWithError: error) }
            if let id = id {
                let message = error.localizedDescription
                VeriventURLProtocol.captureQueue.async {
                    NativeNetwork.shared.fail(id: id, message: message, durationMillis: elapsed)
                }
            }
            return
        }
        if !silent { client?.urlProtocolDidFinishLoading(self) }
        if let id = id, let response = response {
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            let headers = VeriventURLProtocol.headerFields(of: response)
            VeriventURLProtocol.captureQueue.async {
                NativeNetwork.shared.complete(
                    id: id,
                    status: Int32(response.statusCode),
                    protocol: negotiated,
                    contentType: contentType,
                    headers: headers,
                    body: body,
                    bodyByteCount: total,
                    durationMillis: elapsed
                )
            }
        }
    }

    /**
     Close this hop at its 3xx and hand the redirect back to the loading system, which re-issues it
     through a fresh instance of this class — one row per hop, the way the Ktor plugin records one
     entry per physical attempt. Following it inside the inner session instead would hide the hops
     and bypass the host's own redirect delegate.
     */
    func redirecting(to newRequest: URLRequest, response: HTTPURLResponse) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let id = callId
        let elapsed = elapsedMillisLocked()
        let task = innerTask
        lock.unlock()

        if let id = id {
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            let headers = VeriventURLProtocol.headerFields(of: response)
            VeriventURLProtocol.captureQueue.async {
                NativeNetwork.shared.complete(
                    id: id,
                    status: Int32(response.statusCode),
                    protocol: nil,
                    contentType: contentType,
                    headers: headers,
                    body: nil,
                    bodyByteCount: 0,
                    durationMillis: elapsed
                )
            }
        }
        // URLSession derives the redirect from the request we marked as handled, and carries the
        // marker across — leaving it on would make `canInit` skip the next hop entirely.
        var forwarded = newRequest
        if let mutable = (newRequest as NSURLRequest).mutableCopy() as? NSMutableURLRequest {
            VeriventURLProtocol.removeProperty(forKey: VeriventURLProtocol.handledKey, in: mutable)
            forwarded = mutable as URLRequest
        }
        client?.urlProtocol(self, wasRedirectedTo: forwarded, redirectResponse: response)
        task?.cancel()
        client?.urlProtocol(
            self,
            didFailWithError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }

    // MARK: - Helpers

    /// Caller holds `lock`.
    private func elapsedMillisLocked() -> Int64 {
        guard let startedAt = startedAt else { return 0 }
        let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt.uptimeNanoseconds
        return Int64(elapsed / 1_000_000)
    }

    private static func headerFields(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String else { continue }
            headers[name] = String(describing: value)
        }
        return headers
    }

    private struct RequestBody {
        let data: Data?
        let byteCount: Int64
        let placeholder: String?
    }

    /**
     `httpBody` is all but always nil by the time a `URLProtocol` sees a request — URLSession has
     already turned it into a stream, even for a plain `dataTask` whose caller set `httpBody`. So
     the stream branch is the normal path: drain it whole and re-attach it as `httpBody` on the
     request we actually send, which is only safe when `Content-Length` says it fits in memory.
     Only the declared length is read: the server takes no more than that, and it bounds memory
     even when the header understates the stream. Throws when the stream fails mid-read.
     */
    private static func captureRequestBody(
        from original: URLRequest,
        into inner: inout URLRequest
    ) throws -> RequestBody {
        if let data = original.httpBody {
            return RequestBody(data: data, byteCount: Int64(data.count), placeholder: nil)
        }
        guard let stream = original.httpBodyStream else {
            return RequestBody(data: nil, byteCount: 0, placeholder: nil)
        }
        let declared = original.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
        guard let length = declared, length <= streamDrainCap else {
            return RequestBody(
                data: nil,
                byteCount: declared ?? -1,
                placeholder: "(streaming body — not captured)"
            )
        }
        let drained = try drain(stream, limit: length)
        inner.httpBodyStream = nil
        inner.httpBody = drained
        return RequestBody(data: drained, byteCount: Int64(drained.count), placeholder: nil)
    }

    private static func drain(_ stream: InputStream, limit: Int64) throws -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Int64(data.count) < limit && stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: min(buffer.count, Int(limit - Int64(data.count))))
            if read < 0 { throw stream.streamError ?? URLError(.unknown) }
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
