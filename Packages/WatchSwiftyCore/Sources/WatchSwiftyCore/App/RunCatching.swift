/// Runs an API call and turns failures into `UserFacingError`; `nil` when the task was cancelled (screen closed).
public func runCatching<T: Sendable>(
    isolation: isolated (any Actor)? = #isolation, _ operation: () async throws -> T
) async -> Result<T, UserFacingError>? {
    do {
        return .success(try await operation())
    } catch {
        if UserFacingError.isCancellation(error) { return nil }
        return .failure(UserFacingError.from(error))
    }
}
