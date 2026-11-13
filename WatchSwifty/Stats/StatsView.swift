import Charts
import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var store: StatsStore?

    var body: some View {
        Group {
            if let store { StatsContent(store: store) } else { StatsSkeleton() }
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
                StatsSkeleton()
            }
        }
        .refreshable { await store.load() }
        .staleBanner(store.stats.value == nil ? nil : store.stats.error) { await store.load() }
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
            Section(stats.year.map { "Jahr " + String($0) } ?? "Zeitraum") {
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
                    Chart(stats.services, id: \.service) { share in
                        SectorMark(angle: .value("Minuten", share.minutes), innerRadius: .ratio(0.55))
                            .foregroundStyle(by: .value("Dienst", share.service?.displayName ?? "Ohne Dienst"))
                    }
                    .frame(height: 220)
                    // Episodes and movies per service arrive from 0.5.0 on; older servers only send the time.
                    if stats.services.contains(where: { $0.episodes != nil || $0.movies != nil }) {
                        ForEach(stats.services, id: \.service) { share in
                            LabeledContent {
                                Text(Self.hours(share.minutes))
                            } label: {
                                Text(share.service?.displayName ?? "Ohne Dienst")
                                let counts = Self.counts([(share.episodes ?? 0, "Folge", "Folgen"), (share.movies ?? 0, "Film", "Filme")])
                                if !counts.isEmpty { Text(counts) }
                            }
                        }
                    }
                }
            }
            if !stats.topSeries.isEmpty {
                Section("Längste Serien") {
                    ForEach(stats.topSeries, id: \.tmdbId) { series in
                        RankedRow(route: .series(series.tmdbId), posterPath: series.posterPath, name: series.name,
                                  detail: "\(Self.count(series.episodes, "Folge", "Folgen")) · \(Self.hours(series.minutes))")
                    }
                }
            }
            if let movies = stats.longestMovies, !movies.isEmpty {
                Section("Längste Filme") {
                    ForEach(movies, id: \.tmdbId) { movie in
                        RankedRow(route: .movie(movie.tmdbId), posterPath: movie.posterPath, name: movie.name, detail: Self.detail(movie))
                    }
                }
            }
            if let series = stats.mostCompletedSeries, !series.isEmpty {
                Section {
                    ForEach(series, id: \.tmdbId) { entry in
                        RankedRow(route: .series(entry.tmdbId), posterPath: entry.posterPath, name: entry.name,
                                  detail: "\(entry.completions)× komplett")
                    }
                } header: {
                    Text("Meistgesehene Serien")
                } footer: {
                    Text("Über alle Jahre.")
                }
            }
            if let movies = stats.mostWatchedMovies, !movies.isEmpty {
                Section("Meistgesehene Filme") {
                    ForEach(movies, id: \.tmdbId) { movie in
                        RankedRow(route: .movie(movie.tmdbId), posterPath: movie.posterPath, name: movie.name, detail: Self.detail(movie))
                    }
                }
            }
            if let episodes = stats.mostWatchedEpisodes, !episodes.isEmpty {
                Section("Meistgesehene Folgen") {
                    ForEach(episodes, id: \.self) { episode in
                        RankedRow(route: .series(episode.tmdbId), posterPath: episode.posterPath, name: episode.seriesName,
                                  detail: ["S\(episode.season)E\(episode.number)", episode.name].filter { !$0.isEmpty }
                                      .joined(separator: " ") + " · \(episode.watches)×")
                    }
                }
            }
            if let genres = stats.genres, !genres.isEmpty {
                Section {
                    Chart(genres, id: \.genre) { stat in
                        BarMark(x: .value("Stunden", Double(stat.seriesMinutes) / 60), y: .value("Genre", stat.genre.displayName))
                            .foregroundStyle(by: .value("Art", "Serien"))
                        BarMark(x: .value("Stunden", Double(stat.movieMinutes) / 60), y: .value("Genre", stat.genre.displayName))
                            .foregroundStyle(by: .value("Art", "Filme"))
                    }
                    .chartYScale(domain: genres.map(\.genre.displayName))
                    .frame(height: CGFloat(genres.count) * 28 + 40)
                    ForEach(genres, id: \.genre) { stat in
                        LabeledContent {
                            Text(Self.hours(stat.seriesMinutes + stat.movieMinutes))
                        } label: {
                            Text(stat.genre.displayName)
                            let counts = Self.counts([(stat.series, "Serie", "Serien"), (stat.movies, "Film", "Filme")])
                            if !counts.isEmpty { Text(counts) }
                        }
                    }
                } header: {
                    Text("Genres")
                } footer: {
                    Text("Ein Titel zählt bei jedem seiner Genres; Titel, deren Genres noch nicht geladen sind, fehlen.")
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

    /// „1 Folge“, „80 Folgen“ (as in the web).
    static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }

    /// „12 Folgen · 3 Filme“, leaving out zeros.
    static func counts(_ parts: [(Int, String, String)]) -> String {
        parts.filter { $0.0 > 0 }.map { count($0.0, $0.1, $0.2) }.joined(separator: " · ")
    }

    /// „2× · 4 Std. 32 Min.“ (time only when the runtime is known).
    static func detail(_ movie: Components.Schemas.MovieStat) -> String {
        "\(movie.watches)×" + (movie.minutes > 0 ? " · \(hours(movie.minutes))" : "")
    }
}

/// One entry of a ranked list (longest or most watched titles): poster, name, detail, link to the title.
private struct RankedRow: View {
    let route: Route
    let posterPath: String?
    let name: String
    let detail: String

    var body: some View {
        NavigationLink(value: route) {
            HStack {
                PosterImage(path: posterPath, width: 36)
                VStack(alignment: .leading) {
                    Text(name)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
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
