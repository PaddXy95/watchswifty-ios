import SwiftUI
import WatchSwiftyClient

/// Poster, title, year/status and the overview of a series or movie.
struct TitleHeader: View {
    let posterPath: String?
    let title: String
    let subtitle: String
    let overview: String?
    @State private var expanded = false
    @State private var showPoster = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Button { showPoster = posterPath != nil } label: { PosterImage(path: posterPath, width: 100) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Poster vergrößern")
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    if !subtitle.isEmpty { Text(subtitle).foregroundStyle(.secondary) }
                }
            }
            if let overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .lineLimit(expanded ? nil : 4)
                    .onTapGesture { expanded.toggle() }
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(isPresented: $showPoster) {
            if let posterPath { PosterViewer(path: posterPath, title: title) }
        }
    }
}

/// TMDB, IMDb, Rotten Tomatoes, SeriesGraph as in the web.
struct LinksRow: View {
    let links: Components.Schemas.Links

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                link("TMDB", links.tmdb)
                link("IMDb", links.imdb)
                link("Rotten Tomatoes", links.rottenTomatoes)
                if let graph = links.seriesGraph { link("SeriesGraph", graph) }
            }
        }
    }

    @ViewBuilder private func link(_ title: String, _ url: String) -> some View {
        if let destination = URL(string: url) {
            Link(title, destination: destination)
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }
}
