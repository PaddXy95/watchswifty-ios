import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct EpisodeRow: View {
    let episode: Components.Schemas.Episode

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: episode.watches.isEmpty ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(episode.watches.isEmpty ? Color.secondary : Color.green)
                .accessibilityLabel(episode.watches.isEmpty ? "Nicht gesehen" : "Gesehen")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(episode.number). \(episode.name)")
                    .foregroundStyle(episode.aired ? .primary : .secondary)
                if let airDate = episode.airDate {
                    Text(episode.aired ? Day.display(airDate) : "Erscheint am \(Day.display(airDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if episode.watches.count > 1 {
                Text("\(episode.watches.count)×").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The watches of one episode (date, service, imported or not).
struct WatchesSheet: View {
    let episode: Components.Schemas.Episode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(episode.watches, id: \.id) { watch in
                VStack(alignment: .leading) {
                    Text(watch.day.map { Day.display($0) } ?? "Ohne Datum")
                    Text([watch.service?.displayName, watch.origin == .import ? "Import" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("S\(episode.season)E\(episode.number) · \(episode.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
