import WatchSwiftyClient

/// Which service a new watch gets.
public enum ServiceChoice: Sendable, Equatable, Hashable {
    /// The service last used for this series (server default).
    case lastUsed
    /// „Ohne Dienst“.
    case none
    case service(ServiceValue)
}

/// Date, service and rewatch flag for marking something as watched (sheet „Gesehen am …“).
public struct WatchChoice: Sendable, Equatable {
    /// `yyyy-MM-dd`; `nil` means today (the server's today).
    public var day: String?
    public var service: ServiceChoice
    public var rewatch: Bool

    public init(day: String? = nil, service: ServiceChoice = .lastUsed, rewatch: Bool = false) {
        self.day = day
        self.service = service
        self.rewatch = rewatch
    }

    public var input: Components.Schemas.WatchInput {
        let service: Components.Schemas.WatchInput.servicePayload? = switch self.service {
        case .lastUsed: nil
        case .none: .unknown
        // A value this app does not know cannot be sent in the closed request enum: fall back to the server default.
        case .service(let value): .init(rawValue: value.rawValue)
        }
        return .init(day: day, service: service, rewatch: rewatch ? true : nil)
    }
}
