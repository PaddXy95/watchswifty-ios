/// State of something a screen loads: the old value stays visible while reloading and after an error.
public struct Loadable<Value: Sendable>: Sendable {
    public var value: Value?
    public var isLoading = false
    public var error: UserFacingError?
    /// `AppModel.changeVersion` when the value was requested.
    public var loadedAt: Int?

    public init(value: Value? = nil) { self.value = value }

    /// True when never loaded or something changed since (reload on next appearance).
    public func isStale(_ changeVersion: Int) -> Bool { loadedAt != changeVersion }

    public mutating func begin() {
        isLoading = true
        error = nil
    }

    public mutating func finish(_ result: Result<Value, UserFacingError>, at changeVersion: Int) {
        isLoading = false
        switch result {
        case .success(let value):
            self.value = value
            loadedAt = changeVersion
        case .failure(let error):
            self.error = error
        }
    }

    /// Loading was cancelled: keep what is there.
    public mutating func cancel() { isLoading = false }
}
