import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

/// One viewing of an episode or movie (date, service, import) with „Löschen“. The caller asks first („Diese Sichtung
/// löschen?“, as in the web) and deletes just this one.
struct WatchRow: View {
    let watch: Components.Schemas.WatchSummary
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(watch.day.map { Day.display($0) } ?? "Ohne Datum")
                let details = [watch.service?.displayName, watch.origin == .import ? "Import" : nil].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
    }
}
