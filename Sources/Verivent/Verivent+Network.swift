import Foundation
import VeriventKit

extension Verivent {

    /// A request as `URLSession` described it, handed to the `keepRequest` filter.
    public struct Request {
        public let method: String
        public let url: String
        public let host: String
        public let path: String
        public let headers: [String: String]

        fileprivate init(_ raw: NativeRequest) {
            method = raw.method
            url = raw.url
            host = raw.host
            path = raw.path
            headers = raw.headers as? [String: String] ?? [:]
        }
    }

    /**
     **Experimental.** Capture every HTTP request made through `configuration`, and show it in the
     inspector next to your analytics events. The shape of this API may change in a minor release.

     ```swift
     let configuration = URLSessionConfiguration.default
     Verivent.installNetworkInterceptor(on: configuration)
     let session = URLSession(configuration: configuration)
     ```

     What it does not see, because `URLProtocol` cannot: `URLSession.shared` (its `protocolClasses`
     is not configurable), WebSockets, background sessions, and any session a third-party SDK builds
     for itself. And because the request is replayed through Verivent's own session, **your
     `URLSessionDelegate` is not consulted for intercepted requests** — certificate pinning or a
     credential you would have supplied in `didReceive challenge:` does not run, and the connection
     falls back to the system's default trust evaluation. That is no weaker than not intercepting at
     all, but it does drop a check you added; if you rely on one, leave that configuration alone.

     Installing on a second configuration replaces this configuration's options: the interceptor
     keeps one set of settings for the process, so the last call wins.

     Both closures are held until the next call — in practice for the life of the process — so
     capture `[weak self]` if one reaches into an object you expect to be deallocated.

     - Parameters:
       - maxContentLength: bodies past this are captured truncated and flagged in the viewer.
       - redactHeader: redact matching headers. `Authorization`, `Cookie` and `Set-Cookie` are
         always redacted on top of this.
       - redactQueryParameter: redact matching query parameters in the captured URL. Common
         secret-bearing names (`api_key`, `token`, …) are always redacted on top of this.
       - redactBody: rewrite a captured body preview before it is stored.
       - keepRequest: capture a request only when this returns true.
     */
    public static func installNetworkInterceptor(
        on configuration: URLSessionConfiguration,
        maxContentLength: Int64 = NativeNetwork.shared.defaultMaxContentLength,
        redactHeader: ((String) -> Bool)? = nil,
        redactQueryParameter: ((String) -> Bool)? = nil,
        redactBody: ((String) -> String)? = nil,
        keepRequest: ((Request) -> Bool)? = nil
    ) {
        NativeNetwork.shared.configure(
            maxContentLength: maxContentLength,
            redactHeader: redactHeader.map { predicate in { KotlinBoolean(bool: predicate($0)) } },
            redactQueryParameter: redactQueryParameter.map { predicate in
                { KotlinBoolean(bool: predicate($0)) }
            },
            redactBody: redactBody,
            keepRequest: keepRequest.map { predicate in
                { raw in KotlinBoolean(bool: predicate(Request(raw))) }
            }
        )
        InnerSession.shared.adopt(configuration)

        // At the front, and de-duplicated: appended, a protocol already in the list would claim the
        // request first and Verivent would never see it.
        var classes = configuration.protocolClasses ?? []
        classes.removeAll { $0 == VeriventURLProtocol.self }
        configuration.protocolClasses = [VeriventURLProtocol.self] + classes
    }
}
