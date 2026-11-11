import SwiftUI
import WatchSwiftyCore

/// Login in the browser sheet (password or SSO), then „Verbinden“ on the server's consent page.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var error: UserFacingError?
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "tv")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Bei WatchSwifty anmelden")
                    .font(.title2.bold())
                if let host = model.server?.baseURL.host() {
                    Text(host).foregroundStyle(.secondary)
                }
                if let notice = model.notice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
                if let error {
                    Text(error.message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button {
                    signIn()
                } label: {
                    if isSigningIn { ProgressView() } else { Text("Anmelden").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSigningIn)
                Text("Die Anmeldung läuft im Browser-Fenster deines Servers. Die App sieht dein Passwort nie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Anderen Server wählen") {
                    Task { await model.forgetServer() }
                }
                .font(.footnote)
            }
            .padding()
        }
    }

    private func signIn() {
        isSigningIn = true
        error = nil
        Task {
            defer { isSigningIn = false }
            do { try await model.signIn(using: ASWebAuthenticator()) } catch { self.error = UserFacingError.from(error) }
        }
    }
}
