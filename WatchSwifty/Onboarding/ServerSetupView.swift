import SwiftUI
import WatchSwiftyCore

/// First start: which server, and how this device is called in the device list.
struct ServerSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var error: UserFacingError?
    @State private var isChecking = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("Server-Adresse", text: $address, prompt: Text("https://watch.example.de"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .onSubmit(connect)
                } header: {
                    Text("Server")
                } footer: {
                    if let error {
                        Text(error.message).foregroundStyle(.red)
                    } else {
                        Text("Die Adresse deines WatchSwifty-Servers – per HTTPS oder über dein VPN.")
                    }
                }
                Section {
                    TextField("Gerätename", text: $model.deviceName)
                } header: {
                    Text("Gerätename")
                } footer: {
                    Text("So erscheint dieses Gerät unter Konto → Geräte.")
                }
                Section {
                    Button(action: connect) {
                        HStack {
                            Text("Weiter")
                            if isChecking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isChecking || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("WatchSwifty")
        }
    }

    private func connect() {
        guard !isChecking else { return }
        isChecking = true
        error = nil
        Task {
            defer { isChecking = false }
            do { try await model.connect(to: address) } catch { self.error = UserFacingError.from(error) }
        }
    }
}

#Preview {
    ServerSetupView()
        .environment(AppModel(environment: AppEnvironment(tokenStore: InMemoryTokenStore(),
                                                          settings: UserDefaults(suiteName: "preview")!,
                                                          transport: FakeTransport(),
                                                          snapshot: SnapshotCache(directory: FileManager.default.temporaryDirectory))))
}
