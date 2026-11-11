import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct ImportsView: View {
    var body: some View {
        List {
            NavigationLink(value: ImportDestination.netflix) {
                Label("Netflix-Verlauf", systemImage: "square.and.arrow.down")
            }
            NavigationLink(value: ImportDestination.filmList) {
                Label("Filmliste", systemImage: "film.stack")
            }
        }
        .navigationTitle("Importe")
        .navigationDestination(for: ImportDestination.self) { destination in
            switch destination {
            case .netflix: NetflixImportView()
            case .filmList: FilmListView()
            }
        }
    }
}

enum ImportDestination: Hashable {
    case netflix, filmList
}

extension MappingStatusValue {
    var label: String {
        switch self {
        case .pending: "Offen"
        case .auto: "Automatisch"
        case .confirmed: "Bestätigt"
        case .review: "Zu prüfen"
        case .ignored: "Ignoriert"
        default: rawValue
        }
    }
}
