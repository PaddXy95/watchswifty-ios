import SwiftUI
import WatchSwiftyCore

struct ServerSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                if let server = model.server {
                    LabeledContent("Adresse", value: server.baseURL.absoluteString)
                }
                LabeledContent("Gerätename", value: model.deviceName)
            } footer: {
                if model.server?.isInsecure == true {
                    Label("Unverschlüsselte Verbindung – nur im Heimnetz oder VPN verwenden.", systemImage: "lock.open")
                }
            }
            Section {
                Button("Abmelden", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text("Meldet dieses Gerät beim Server ab. Danach ist eine neue Anmeldung nötig.")
            }
        }
        .navigationTitle("Server")
        .confirmationDialog("Dieses Gerät abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await model.signOut() } }
        }
    }
}
