import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var store: HistoryStore?

    var body: some View {
        Group {
            if let store { HistoryContent(store: store) } else { ListSkeleton() }
        }
        .navigationTitle("Verlauf")
        .task {
            if store == nil { store = HistoryStore(api: model.api, app: model) }
            await store?.reloadIfStale()
        }
    }
}

private struct HistoryContent: View {
    @Bindable var store: HistoryStore
    @State private var editing: Components.Schemas.HistoryItem?
    @State private var deleting: Components.Schemas.HistoryItem?

    /// Watches grouped by day, in server order (newest first).
    private var groups: [(day: String, items: [Components.Schemas.HistoryItem])] {
        var result: [(day: String, items: [Components.Schemas.HistoryItem])] = []
        for item in store.items {
            let day = item.day.map { Day.display($0) } ?? "Ohne Datum"
            if result.last?.day == day { result[result.count - 1].items.append(item) } else { result.append((day, [item])) }
        }
        return result
    }

    var body: some View {
        Group {
            if store.items.isEmpty, let error = store.error {
                ErrorView(error: error) { await store.loadFirstPage() }
            } else if store.items.isEmpty, !store.hasLoaded {
                ListSkeleton()
            } else if store.items.isEmpty, store.hasLoaded {
                ContentUnavailableView("Noch nichts gesehen", systemImage: "clock",
                                       description: Text("Markierte Folgen und Filme erscheinen hier."))
            } else {
                List {
                    ForEach(groups, id: \.day) { group in
                        Section(group.day) {
                            ForEach(group.items, id: \.id) { item in
                                HistoryRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = item }
                                    .swipeActions {
                                        Button("Löschen", systemImage: "trash", role: .destructive) { deleting = item }
                                    }
                                    .task { await store.loadMoreIfNeeded(after: item) }
                            }
                        }
                    }
                    if store.isLoading, store.hasLoaded { SkeletonRows(count: 2) }
                }
                .disabled(store.busy)
            }
        }
        .refreshable { await store.loadFirstPage() }
        .onAppear { Task { await store.reloadIfStale() } }
        .sheet(item: $editing) { item in
            EditWatchSheet(item: item) { day, service in
                Task { await store.update(id: item.id, day: day, service: service) }
            }
        }
        .confirmationDialog("Sichtung löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { item in
            Button("Löschen", role: .destructive) { Task { await store.delete(id: item.id) } }
        } message: { item in
            Text(item.title)
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
    }
}

private struct HistoryRow: View {
    let item: Components.Schemas.HistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
            if let episode = item.episode {
                Text("S\(episode.season)E\(episode.number) · \(episode.name)").font(.subheadline).lineLimit(1)
            }
            Text([item.kind == .movie ? "Film" : nil, item.service?.displayName, item.origin == .import ? "Import" : nil]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Components.Schemas.HistoryItem: @retroactive Identifiable {}

/// Edit date and service of one watch; an unknown service stays as it is unless changed.
struct EditWatchSheet: View {
    let item: Components.Schemas.HistoryItem
    let onSave: (String?, ServiceValue?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var service: ServiceChoice

    init(item: Components.Schemas.HistoryItem, onSave: @escaping (String?, ServiceValue?) -> Void) {
        self.item = item
        self.onSave = onSave
        _hasDate = State(initialValue: item.day != nil)
        _date = State(initialValue: item.day.flatMap { Day.date(from: $0) } ?? Date())
        _service = State(initialValue: item.service.map { .service($0) } ?? .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Mit Datum", isOn: $hasDate)
                if hasDate { DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date) }
                ServicePicker(selection: $service, allowsLastUsed: false)
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let serviceValue: ServiceValue? = if case .service(let value) = service { value } else { nil }
                        onSave(hasDate ? Day.string(from: date) : nil, serviceValue)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
