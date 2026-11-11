import SwiftUI
import WatchSwiftyCore

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Start", systemImage: "play.circle") {
                NavigationStack { StartView().withRoutes() }
            }
            Tab("Bibliothek", systemImage: "books.vertical") {
                NavigationStack { LibraryView().withRoutes() }
            }
            Tab("Verlauf", systemImage: "clock") {
                NavigationStack { HistoryView().withRoutes() }
            }
            Tab("Mehr", systemImage: "ellipsis.circle") {
                NavigationStack { MoreView().withRoutes() }
            }
            Tab("Suche", systemImage: "magnifyingglass", role: .search) {
                NavigationStack { SearchView().withRoutes() }
            }
        }
    }
}

/// Stand-in for screens that follow in later steps.
struct PlaceholderView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer")
            .navigationTitle(title)
    }
}
