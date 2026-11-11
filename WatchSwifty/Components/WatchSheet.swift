import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

/// „Gesehen am …“: date, service (last used / none / a service) and „Erneut gesehen“.
struct WatchSheet: View {
    let title: String
    let onSave: (WatchChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var service: ServiceChoice = .lastUsed
    @State private var rewatch: Bool

    init(title: String, rewatch: Bool = false, onSave: @escaping (WatchChoice) -> Void) {
        self.title = title
        self.onSave = onSave
        _rewatch = State(initialValue: rewatch)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date)
                ServicePicker(selection: $service)
                Toggle("Erneut gesehen", isOn: $rewatch)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let day = Calendar.current.isDateInToday(date) ? nil : Day.string(from: date)
                        onSave(WatchChoice(day: day, service: service, rewatch: rewatch))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ServicePicker: View {
    @Binding var selection: ServiceChoice
    var allowsLastUsed = true

    var body: some View {
        Picker("Dienst", selection: $selection) {
            if allowsLastUsed { Text("Zuletzt genutzt").tag(ServiceChoice.lastUsed) }
            Text("Ohne Dienst").tag(ServiceChoice.none)
            ForEach(ServiceValue.known, id: \.self) { service in
                Text(service.displayName).tag(ServiceChoice.service(service))
            }
            if case .service(let current) = selection, !current.isKnown {
                Text(current.displayName).tag(selection)
            }
        }
    }
}
