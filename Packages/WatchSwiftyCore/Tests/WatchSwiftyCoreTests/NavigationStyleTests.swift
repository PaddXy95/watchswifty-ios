import Foundation
import Testing

/// Every tab is one `NavigationStack` whose screens are pushed by value (`Route`, `MoreDestination`, …). A
/// view-destination link (`NavigationLink { … }`) or a binding destination (`navigationDestination(isPresented:)` /
/// `(item:)`) in the same stack makes SwiftUI push and pop in a loop as soon as a value link follows it (seen on
/// „Demnächst“ and on Konto → „Beobachtete Serien“). So do a second stack inside a pushed screen and a destination type
/// registered twice. The app target has no test bundle, so `NavigationLint` scans its sources.
@Suite struct NavigationStyleTests {
    static let appFolder = URL(filePath: #filePath)
        .deletingLastPathComponent()   // WatchSwiftyCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // WatchSwiftyCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repository root
        .appending(path: "WatchSwifty")

    private func lint(_ path: String, _ text: String) -> [String] {
        NavigationLint.problems(in: [.init(path: path, text: text)])
    }

    private func locations(_ problems: [String]) -> [String] {
        problems.map { String($0.prefix { $0 != " " }) }
    }

    @Test func flagsViewDestinationLinks() {
        let problems = lint("A.swift", #"""
        struct A: View {
            var body: some View {
                NavigationLink { B() } label: { Text("B") }
                NavigationLink(
                    "Geräte"
                ) { DevicesView() }
            }
        }
        """#)
        #expect(locations(problems) == ["A.swift:3:", "A.swift:4:"])
    }

    @Test func acceptsValueLinksOnSeveralLines() {
        let problems = lint("A.swift", #"""
        struct A: View {
            var body: some View {
                NavigationLink(series.name, value: Route.series(series.tmdbId))
                NavigationLink(
                    value: entry.kind == .tv ? Route.series(entry.tmdbId) : Route.movie(entry.tmdbId)
                ) {
                    Text("Folge (neu)")
                }
            }
        }
        """#)
        #expect(problems.isEmpty)
    }

    @Test func flagsBindingDestinations() {
        let problems = lint("A.swift", #"""
        struct A: View {
            var body: some View {
                List {}
                    .navigationDestination(isPresented: $showUpcoming) { UpcomingView() }
                    .navigationDestination(
                        item: $selected
                    ) { SeriesView(tmdbID: $0) }
            }
        }
        """#)
        #expect(locations(problems) == ["A.swift:4:", "A.swift:5:"])
    }

    @Test func ignoresCommentsButNotURLsInStrings() {
        let problems = lint("A.swift", #"""
        /// Mixing it with `navigationDestination(isPresented:)` loops; so does `NavigationLink { … }`.
        struct A: View {
            // NavigationLink { Old() } label: { Text("old") }
            /* .navigationDestination(item: $old) { Old() } */
            var body: some View {
                let docs = "https://example.org/docs"; NavigationLink { Docs(docs) } label: { Text("Hilfe") }
            }
        }
        """#)
        #expect(locations(problems) == ["A.swift:6:"])
    }

    @Test func flagsNavigationStackOutsideTabsOnboardingAndSheets() {
        let problems = NavigationLint.problems(in: [
            .init(path: "MainTabView.swift", text: "struct MainTabView: View { var body: some View { NavigationStack { StartView() } } }"),
            .init(path: "Onboarding/LoginView.swift", text: "struct LoginView: View { var body: some View { NavigationStack { Form {} } } }"),
            .init(path: "Feature/FeatureView.swift", text: #"""
            struct FeatureView: View {
                var body: some View {
                    NavigationStack { List {} }
                }
            }

            private struct RenameSheet: View {
                var body: some View {
                    NavigationStack { Form {} }
                }
            }
            """#),
        ])
        #expect(locations(problems) == ["Feature/FeatureView.swift:3:"])
    }

    @Test func flagsDestinationTypeRegisteredTwice() {
        let problems = NavigationLint.problems(in: [
            .init(path: "Route.swift", text: "extension View { func withRoutes() -> some View { navigationDestination(for: Route.self) { _ in X() } } }"),
            .init(path: "Series/SeriesView.swift", text: "struct SeriesView: View { var body: some View { List {}.navigationDestination(for: Route.self) { _ in Y() } } }"),
            .init(path: "More/MoreView.swift", text: "struct MoreView: View { var body: some View { List {}.navigationDestination(for: MoreDestination.self) { _ in Z() } } }"),
        ])
        #expect(problems.count == 1)
        #expect(problems.first?.contains("Route.self") == true)
        #expect(problems.first?.contains("Series/SeriesView.swift:1") == true)
    }

    @Test func appNavigationCannotLoop() throws {
        let root = Self.appFolder.standardizedFileURL.path + "/"
        let sources = try #require(FileManager.default.enumerator(at: Self.appFolder, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { url in
                NavigationLint.Source(path: url.standardizedFileURL.path.replacingOccurrences(of: root, with: ""),
                                      text: try String(contentsOf: url, encoding: .utf8))
            }
        #expect(sources.count > 20)
        let problems = NavigationLint.problems(in: sources)
        #expect(problems.isEmpty, "Navigation that can loop:\n\(problems.joined(separator: "\n"))")
    }
}
