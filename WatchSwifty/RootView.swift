import SwiftUI
import WatchSwiftyCore

/// Chooses the screen from the connection state.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .launching:
            Color(.systemGroupedBackground).ignoresSafeArea()
        case .needsServer:
            ServerSetupView()
        case .needsLogin:
            LoginView()
        case .serverTooOld(let server, let minimum):
            ServerTooOldView(server: server, minimum: minimum)
        case .ready:
            MainTabView()
        }
    }
}
