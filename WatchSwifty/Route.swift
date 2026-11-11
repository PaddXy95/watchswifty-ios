import SwiftUI

/// Detail screens reachable from every tab.
enum Route: Hashable {
    case series(Int)
    case movie(Int)
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .series(let id): SeriesView(tmdbID: id)
            case .movie(let id): MovieView(tmdbID: id)
            }
        }
    }
}
