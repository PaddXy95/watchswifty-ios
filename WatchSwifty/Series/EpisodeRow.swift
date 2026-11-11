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
        .contentShape(Rectangle())
    }
}

/// One episode: synopsis, every watch, and marking it (again) with a date, service and „Erneut gesehen“.
struct EpisodeSheet: View {
    let store: SeriesStore
    let target: EpisodeTarget
    let onMarked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var service: ServiceChoice = .lastUsed
    @State private var rewatch = false
    @State private var confirmUnmark = false

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
                                LabeledContent(watch.day.map { Day.display($0) } ?? "Ohne Datum") {
                                    Text([watch.service?.displayName, watch.origin == .import ? "Import" : nil]
                                        .compactMap { $0 }.joined(separator: " · "))
                                }
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
                        if !episode.watches.isEmpty {
                            Section {
                                Button("Nicht gesehen", systemImage: "xmark.circle", role: .destructive) { confirmUnmark = true }
                            }
                        }
                    }
                }
            }
            .navigationTitle("S\(target.season)E\(target.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .onAppear { rewatch = !(episode?.watches.isEmpty ?? true) }
            .confirmationDialog("Als nicht gesehen markieren?", isPresented: $confirmUnmark, titleVisibility: .visible) {
                Button("Nicht gesehen", role: .destructive) {
                    Task {
                        await store.unmarkEpisode(season: target.season, number: target.number)
                        if store.actionError == nil { dismiss() }
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
