import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct EpisodeRow: View {
    let episode: Components.Schemas.Episode

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: episode.watches.isEmpty ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(episode.watches.isEmpty ? Color.secondary : Color.green)
                .contentTransition(.symbolEffect(.replace))
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
        .contentShape(Rectangle())
    }
}

/// One episode: synopsis, every watch (each deletable on its own), and marking it (again) with a date, service and
/// „Erneut gesehen“.
struct EpisodeSheet: View {
    let store: SeriesStore
    let target: EpisodeTarget
    let onMarked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var service: ServiceChoice = .lastUsed
    @State private var rewatch = false
    @State private var deleting: Components.Schemas.WatchSummary?

    private var episode: Components.Schemas.Episode? {
        store.detail.value?.seasons.first { $0.number == target.season }?.episodes.first { $0.number == target.number }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let episode {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(episode.name).font(.headline)
                            Text(facts(episode)).font(.caption).foregroundStyle(.secondary)
                            if let overview = episode.overview, !overview.isEmpty {
                                Text(overview).font(.callout).padding(.top, 4)
                            } else {
                                Text("Keine Beschreibung vorhanden.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if !episode.watches.isEmpty {
                        Section("Gesehen") {
                            ForEach(episode.watches, id: \.id) { watch in
                                WatchRow(watch: watch) { deleting = watch }
                            }
                        }
                    }
                    if episode.aired {
                        Section(episode.watches.isEmpty ? "Als gesehen markieren" : "Noch einmal gesehen") {
                            DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date)
                            ServicePicker(selection: $service)
                            if !episode.watches.isEmpty { Toggle("Erneut gesehen", isOn: $rewatch) }
                            Button("Sichern", systemImage: "checkmark.circle") {
                                let day = Calendar.current.isDateInToday(date) ? nil : Day.string(from: date)
                                Task {
                                    await store.markEpisode(season: target.season, number: target.number,
                                                            choice: WatchChoice(day: day, service: service, rewatch: rewatch))
                                    if store.actionError == nil { onMarked(); dismiss() }
                                }
                            }
                            .disabled(store.busy)
                        }
                    }
                }
            }
            .navigationTitle("S\(target.season)E\(target.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .onAppear { rewatch = !(episode?.watches.isEmpty ?? true) }
            .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                    set: { if !$0 { store.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.actionError?.message ?? "")
            }
            .confirmationDialog("Diese Sichtung löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { watch in
                Button("Löschen", role: .destructive) {
                    Task {
                        await store.deleteWatch(id: watch.id)
                        // The sheet stays open on the episode; the toggle follows whether a viewing is left.
                        rewatch = !(episode?.watches.isEmpty ?? true)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func facts(_ episode: Components.Schemas.Episode) -> String {
        [episode.airDate.map { (episode.aired ? "" : "Erscheint am ") + Day.display($0) },
         episode.runtime.map { "\($0) Min." }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
