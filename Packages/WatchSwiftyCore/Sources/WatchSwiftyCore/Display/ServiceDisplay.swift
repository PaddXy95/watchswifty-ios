import WatchSwiftyClient

extension ServiceValue {
    /// Same labels as the web UI (`StreamingService.label` on the server); values from a newer server are shown
    /// neutrally.
    public var displayName: String {
        switch self {
        case .netflix: "Netflix"
        case .primeVideo: "Prime Video"
        case .disneyPlus: "Disney+"
        case .appleTV: "Apple TV+"
        case .hboMax: "HBO Max"
        case .paramountPlus: "Paramount+"
        case .wow: "WOW"
        case .cinema: "Kino"
        case .purchased: "Gekauft"
        case .other: "Sonstiges"
        default: "Anderer Dienst"
        }
    }
}
