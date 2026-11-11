import SwiftUI
import WatchSwiftyCore

struct ServerTooOldView: View {
    @Environment(AppModel.self) private var model
    let server: String
    let minimum: String

    var body: some View {
        ContentUnavailableView {
            Label("Server zu alt", systemImage: "arrow.up.circle")
        } description: {
            Text("Der Server ist zu alt (\(server)). Diese App braucht mindestens \(minimum).")
        } actions: {
            Button("Erneut prüfen") { Task { await model.start() } }
                .buttonStyle(.borderedProminent)
            Button("Anderen Server wählen") { Task { await model.forgetServer() } }
        }
    }
}
