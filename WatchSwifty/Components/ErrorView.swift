import SwiftUI
import WatchSwiftyCore

/// A screen that could not load: the message as the server or the app says it, with „Erneut versuchen“; without a
/// TMDB token also „TMDB-Token eintragen“.
struct ErrorView: View {
    let error: UserFacingError
    let retry: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var tokenStore: AccountStore?

    var body: some View {
        ContentUnavailableView {
            Label(error.kind == .offline ? "Keine Verbindung" : "Fehler",
                  systemImage: error.kind == .offline ? "wifi.slash" : "exclamationmark.triangle")
        } description: {
            Text(error.message)
        } actions: {
            if error.kind == .missingTMDBToken {
                Button("TMDB-Token eintragen") { tokenStore = AccountStore(api: model.api, app: model) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Erneut versuchen") { Task { await retry() } }
                .buttonStyle(.bordered)
        }
        .sheet(isPresented: Binding(get: { tokenStore != nil }, set: { if !$0 { tokenStore = nil } })) {
            if let tokenStore {
                TMDBTokenSheet(store: tokenStore) { Task { await retry() } }
            }
        }
    }
}
