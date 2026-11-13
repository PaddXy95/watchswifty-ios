import Foundation
import WatchSwiftyClient

extension GenreValue {
    /// Same labels as the web UI (`Genre.label` on the server); a genre from a newer server is shown neutrally.
    public var displayName: String {
        switch self {
        case .action: "Action"
        case .adventure: "Abenteuer"
        case .animation: "Animation"
        case .comedy: "Komödie"
        case .crime: "Krimi"
        case .documentary: "Dokumentation"
        case .drama: "Drama"
        case .family: "Familie"
        case .fantasy: "Fantasy"
        case .history: "Historie"
        case .horror: "Horror"
        case .music: "Musik"
        case .mystery: "Mystery"
        case .romance: "Liebesfilm"
        case .scienceFiction: "Science-Fiction"
        case .tvMovie: "TV-Film"
        case .thriller: "Thriller"
        case .war: "Krieg"
        case .western: "Western"
        case .kids: "Kinder"
        case .news: "Nachrichten"
        case .reality: "Reality"
        case .soap: "Soap"
        case .talk: "Talk"
        case .politics: "Politik"
        default: "Anderes Genre"
        }
    }

    /// Distinct genres sorted by their German label, as the web's genre filter lists them.
    public static func sortedByName(_ genres: some Sequence<GenreValue>) -> [GenreValue] {
        let locale = Locale(identifier: "de_DE")
        return Array(Set(genres)).sorted { $0.displayName.compare($1.displayName, locale: locale) == .orderedAscending }
    }

    /// „Krimi · Drama“ for a title header; empty when the server sends no genres (older servers, not loaded yet).
    public static func line(_ genres: [GenreValue]?) -> String {
        (genres ?? []).map(\.displayName).joined(separator: " · ")
    }
}
