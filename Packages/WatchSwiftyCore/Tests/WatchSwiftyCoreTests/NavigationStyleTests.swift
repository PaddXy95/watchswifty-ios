import Foundation
import Testing

/// Every tab is one `NavigationStack` whose detail screens are pushed by value (`Route`). A view-destination link
/// (`NavigationLink { … }`) or `navigationDestination(isPresented:)` in the same stack makes SwiftUI push and pop in a
/// loop as soon as a value link follows it (seen on „Demnächst“ and on Konto → „Beobachtete Serien“). The app target
/// has no test bundle, so this scans its sources.
@Suite struct NavigationStyleTests {
    static let appSources = URL(filePath: #filePath)
        .deletingLastPathComponent()   // WatchSwiftyCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // WatchSwiftyCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repository root
        .appending(path: "WatchSwifty")

    @Test func appUsesOnlyValueBasedNavigation() throws {
        let files = try #require(FileManager.default.enumerator(at: Self.appSources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)

        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") { continue }
                let viewLink = code.contains("NavigationLink") && !code.contains("value:")
                let flagDestination = code.contains("navigationDestination(isPresented")
                if viewLink || flagDestination {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(code)")
                }
            }
        }
        #expect(offenders.isEmpty, "Use NavigationLink(value:) with navigationDestination(for:):\n\(offenders.joined(separator: "\n"))")
    }
}
