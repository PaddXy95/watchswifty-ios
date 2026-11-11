import Charts
import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var store: StatsStore?

    var body: some View {
        Group {
            if let store { StatsContent(store: store) } else { ProgressView() }
        }
        .navigationTitle("Statistik")
        .task {
            if store == nil { store = StatsStore(api: model.api, app: model) }
            await store?.reloadIfStale()
        }
    }
}

private struct StatsContent: View {
    let store: StatsStore

    var body: some View {
        Group {
            if let stats = store.stats.value {
                list(stats)
            } else if let error = store.stats.error {
                ErrorView(error: error) { await store.load() }
            } else {
                ProgressView()
            }
        }
        .refreshable { await store.load() }
        .toolbar {
            if let years = store.stats.value?.years, !years.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Jahr", selection: Binding(get: { store.year }, set: { year in Task { await store.select(year: year) } })) {
                            Text("Aktuell").tag(Int?.none)
                            ForEach(years, id: \.year) { Text(String($0.year)).tag(Int?.some($0.year)) }
                        }
                    } label: {
                        Label(store.year.map(String.init) ?? "Aktuell", systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                    .fixedSize()
                }
            }
        }
    }

    private func list(_ stats: Components.Schemas.Stats) -> some View {
        List {
            Section(stats.year.map { "Jahr \($0)" } ?? "Zeitraum") {
                PeriodRows(period: stats.period, previous: stats.previous)
            }
            if !stats.chart.isEmpty {
                Section("Verlauf") {
                    Chart(stats.chart, id: \.label) { bar in
                        BarMark(x: .value("Zeit", bar.label), y: .value("Stunden", Double(bar.seriesMinutes) / 60))
                            .foregroundStyle(by: .value("Art", "Serien"))
                        BarMark(x: .value("Zeit", bar.label), y: .value("Stunden", Double(bar.movieMinutes) / 60))
                            .foregroundStyle(by: .value("Art", "Filme"))
                    }
                    .frame(height: 200)
                }
            }
            if !stats.services.isEmpty {
                Section("Dienste") {
                    Chart(stats.services, id: \.minutes) { share in
                        SectorMark(angle: .value("Minuten", share.minutes), innerRadius: .ratio(0.55))
                            .foregroundStyle(by: .value("Dienst", share.service?.displayName ?? "Ohne Dienst"))
                    }
                    .frame(height: 220)
                }
            }
            if !stats.topSeries.isEmpty {
                Section("Meistgesehene Serien") {
                    ForEach(stats.topSeries, id: \.tmdbId) { series in
                        NavigationLink(value: Route.series(series.tmdbId)) {
                            HStack {
                                PosterImage(path: series.posterPath, width: 36)
                                VStack(alignment: .leading) {
                                    Text(series.name)
                                    Text("\(series.episodes) Folgen · \(Self.hours(series.minutes))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !stats.ratings.isEmpty {
                Section("Bewertungen") {
                    Chart(stats.ratings, id: \.rating) { bucket in
                        BarMark(x: .value("Bewertung", bucket.rating.map(String.init) ?? "–"),
                                y: .value("Titel", bucket.movies + bucket.series))
                    }
                    .frame(height: 160)
                }
            }
            Section("Insgesamt") { PeriodRows(period: stats.total, previous: nil) }
            if stats.missingRuntimeTitles > 0 {
                Section {
                    Text("Bei \(stats.missingRuntimeTitles) Titeln fehlt die Laufzeit; ihre Zeit ist nicht mitgezählt.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func hours(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) Std. \(minutes % 60) Min." : "\(minutes) Min."
    }
}

private struct PeriodRows: View {
    let period: Components.Schemas.Period
    let previous: Components.Schemas.Period?

    var body: some View {
        LabeledContent("Folgen", value: "\(period.episodes)")
        LabeledContent("Serien", value: "\(period.series)")
        LabeledContent("Filme", value: "\(period.movies)")
        LabeledContent("Zeit", value: StatsContent.hours(period.minutes))
        if let previous {
            LabeledContent("Vorjahr", value: StatsContent.hours(previous.minutes)).foregroundStyle(.secondary)
        }
    }
}
