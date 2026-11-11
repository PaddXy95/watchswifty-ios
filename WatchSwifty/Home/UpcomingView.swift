import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

/// „Demnächst“: announced episodes of followed series, soonest first; less than three days away is marked.
struct UpcomingView: View {
    let store: HomeStore
    private let today = Day.string(from: Date())

    private var upcoming: [Components.Schemas.UpcomingNote] {
        (store.notes.value?.upcoming ?? []).sorted { ($0.next.airDate ?? "9999") < ($1.next.airDate ?? "9999") }
    }

    var body: some View {
        Group {
            if store.notes.value == nil {
                ListSkeleton(rows: 5)
            } else if upcoming.isEmpty {
                ContentUnavailableView("Nichts angekündigt", systemImage: "calendar",
                                       description: Text("Neue Folgen deiner beobachteten Serien erscheinen hier, sobald sie angekündigt sind."))
            } else {
                List(upcoming, id: \.tmdbId) { note in
                    NavigationLink(value: Route.series(note.tmdbId)) { row(note) }
                }
            }
        }
        .navigationTitle("Demnächst")
        .refreshable { await store.load() }
    }

    private func row(_ note: Components.Schemas.UpcomingNote) -> some View {
        let soon = Day.isSoon(note.next.airDate, today: today)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: soon ? "exclamationmark.circle.fill" : "calendar")
                .foregroundStyle(soon ? Color.red : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.name).font(.headline)
                Text("S\(note.next.season)E\(note.next.number) · \(note.next.name)"
                     + (note.count > 1 ? " (+\(note.count - 1))" : ""))
                    .font(.subheadline).lineLimit(1)
                if let airDate = note.next.airDate {
                    Text([Day.display(airDate), Day.relative(airDate, today: today)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(soon ? Color.red : Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
