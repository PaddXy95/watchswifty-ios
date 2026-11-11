import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct ImportsView: View {
    var body: some View {
        List {
            NavigationLink { NetflixImportView() } label: {
                Label("Netflix-Verlauf", systemImage: "square.and.arrow.down")
            }
            NavigationLink { FilmListView() } label: {
                Label("Filmliste", systemImage: "film.stack")
            }
        }
        .navigationTitle("Importe")
    }
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
