import WatchSwiftyClient

extension NotifyChannelValue {
    /// Same labels as the web UI (Konto → Benachrichtigungen); a channel from a newer server is shown by its raw value.
    public var displayName: String {
        switch self {
        case .mail: "E-Mail"
        case .webhook: "Webhook (KNot)"
        default: rawValue
        }
    }
}
