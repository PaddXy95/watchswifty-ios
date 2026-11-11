import SwiftUI
import WatchSwiftyCore

/// A screen that could not load: the message as the server or the app says it, with „Erneut versuchen“.
struct ErrorView: View {
    let error: UserFacingError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.kind == .offline ? "Keine Verbindung" : "Fehler",
                  systemImage: error.kind == .offline ? "wifi.slash" : "exclamationmark.triangle")
        } description: {
            Text(error.message)
        } actions: {
            Button("Erneut versuchen") { Task { await retry() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
