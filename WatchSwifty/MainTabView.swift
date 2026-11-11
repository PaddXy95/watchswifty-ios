import SwiftUI
import WatchSwiftyCore

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Start", systemImage: "play.circle") {
                NavigationStack { StartView().withRoutes() }
            }
            Tab("Bibliothek", systemImage: "books.vertical") {
                NavigationStack { PlaceholderView(title: "Bibliothek") }
            }
            Tab("Verlauf", systemImage: "clock") {
                NavigationStack { PlaceholderView(title: "Verlauf") }
            }
            Tab("Mehr", systemImage: "ellipsis.circle") {
                NavigationStack { MoreView() }
            }
            Tab("Suche", systemImage: "magnifyingglass", role: .search) {
                NavigationStack { PlaceholderView(title: "Suche") }
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
