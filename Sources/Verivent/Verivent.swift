import Foundation
import VeriventKit

/// Verivent for native iOS hosts: a vendor-agnostic analytics sink plus the web viewer.
///
/// Wraps the Kotlin bridge so nothing Objective-C shaped reaches the call site — no `KotlinBoolean`
/// in your closures, no `.shared` singletons, no `Int32` ports.
public enum Verivent {

    // MARK: - Events

    /// An event as you described it, handed to the `keepEvent` filter.
    public struct Event {
        public let name: String
        public let channel: String
        public let properties: [String: Any]

        fileprivate init(_ raw: NativeEvent) {
            self.name = raw.name
            self.channel = raw.channel
            self.properties = raw.properties as? [String: Any] ?? [:]
        }
    }

    /// Install filtering, redaction and timeline grouping. Grouping parameters left out keep their
    /// current values; a closure left out is cleared, so pass both when adjusting one.
    ///
    /// Both closures are retained until the next `configure` call — for the life of the process in
    /// practice — so capture `[weak self]` if one reaches into an object you expect to go away.
    ///
    /// - Parameters:
    ///   - groupByEvent: event that opens a new group in the viewer; `nil` turns grouping off.
    ///     Applied as events are captured, so it does not regroup what was captured before.
    ///   - groupLabelProperty: property of that event whose value labels the group. When `nil`, or
    ///     absent from the event, the group is labelled with the event's own name.
    ///   - logToConsole: also write each captured event as one JSON line to the unified log
    ///     (`log stream --predicate 'eventMessage BEGINSWITH "VeriventEvent"'`), already redacted.
    public static func configure(
        keepEvent: ((Event) -> Bool)? = nil,
        redactProperty: ((String) -> Bool)? = nil,
        groupByEvent: String? = NativeEvents.shared.groupByEvent,
        groupLabelProperty: String? = NativeEvents.shared.groupLabelProperty,
        logToConsole: Bool = NativeEvents.shared.logToConsole
    ) {
        NativeEvents.shared.configure(
            keepEvent: keepEvent.map { predicate in
                { raw in KotlinBoolean(bool: predicate(Event(raw))) }
            },
            redactProperty: redactProperty.map { predicate in
                { key in KotlinBoolean(bool: predicate(key)) }
            },
            groupByEvent: groupByEvent,
            groupLabelProperty: groupLabelProperty,
            logToConsole: logToConsole
        )
    }

    /// Record one event. Wire this to your own analytics facade, alongside the real SDK call.
    public static func log(_ name: String, channel: String, properties: [String: Any] = [:]) {
        NativeEvents.shared.log(name: name, channel: channel, properties: properties)
    }

    // MARK: - Tracking plan

    /// Where the loaded tracking plan is kept across launches, for example a folder in Application
    /// Support. `nil` keeps it in memory for the life of the process. Setting a folder that already
    /// holds a plan loads it.
    public static var storageDirectory: URL? {
        get { NativeEvents.shared.storageDir.map { URL(fileURLWithPath: $0) } }
        set { NativeEvents.shared.storageDir = newValue?.path }
    }

    /// Validate events captured from now on against the analytics team's tracking plan. Each event
    /// the plan defines then shows whether it matches it, and what breaks it when it doesn't.
    ///
    /// - Throws: when `json` isn't a valid tracking plan; the current plan stays in place.
    public static func loadTrackingPlan(_ json: String) throws {
        try NativeEvents.shared.loadTrackingPlan(json: json)
    }

    public static func clearTrackingPlan() {
        NativeEvents.shared.clearTrackingPlan()
    }

    /// Version of the loaded tracking plan, or `nil` when none is loaded.
    public static var trackingPlanVersion: String? { NativeEvents.shared.trackingPlanVersion }

    // MARK: - Web viewer

    /// Where the viewer listens. `.lan` and `.host` are reachable off-device; `.local` is loopback
    /// only. All of them are token-gated — loopback is shared with every other app on the device.
    public enum Bind {
        case local
        case lan
        case host(String)

        fileprivate var raw: any NativeViewerBind {
            switch self {
            case .local: return NativeViewerBindLocal.shared
            case .lan: return NativeViewerBindLan.shared
            case .host(let address): return NativeViewerBindHost(address: address)
            }
        }
    }

    /// Start the viewer (idempotent). Returns the URL to open, token included.
    ///
    /// The bind happens asynchronously, so a failure (port taken) shows up in the device console
    /// afterwards rather than here; `isWebViewerRunning` flips back to false when it does.
    @discardableResult
    public static func startWebViewer(
        _ bind: Bind = .local,
        port: Int? = nil,
        token: String? = nil
    ) -> String {
        NativeViewer.shared.start(
            bind: bind.raw,
            port: port.map(Int32.init) ?? NativeViewer.shared.defaultPort,
            token: token
        )
    }

    public static func stopWebViewer() {
        NativeViewer.shared.stop()
    }

    public static var isWebViewerRunning: Bool { NativeViewer.shared.isRunning }

    /// The access token every request must carry as `?t=`, or nil when no viewer is running.
    /// Already baked into the URL `startWebViewer` returns; exposed for hand-built requests.
    public static var webViewerToken: String? { NativeViewer.shared.token }

    /// The URL to reach this device from another machine, or nil on a `.local` bind.
    public static var lanURL: String? { NativeViewer.shared.lanUrl() }
}
