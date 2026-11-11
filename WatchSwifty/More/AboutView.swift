import SwiftUI
import WatchSwiftyCore

struct AboutView: View {
    @Environment(AppModel.self) private var model
    @State private var serverVersion: String?

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("App", value: appVersion)
                LabeledContent("Server", value: serverVersion ?? "–")
                if let url = model.server?.baseURL {
                    Link("Weboberfläche öffnen", destination: url)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Link(destination: URL(string: "https://www.themoviedb.org")!) {
                        Image("TMDBLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 16)
                            .accessibilityLabel("TMDB")
                    }
                    Text("Diese Anwendung verwendet TMDB und die TMDB-APIs, ist aber nicht von TMDB unterstützt, zertifiziert oder anderweitig genehmigt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Daten")
            }
        }
        .navigationTitle("Über")
        .task { serverVersion = try? await model.api.getVersion().ok.body.json.version }
    }
}
