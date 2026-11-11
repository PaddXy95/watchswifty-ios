import SwiftUI

/// Rating 1–10 as in the web, or none.
struct RatingControl: View {
    let rating: Int?
    let onChange: (Int?) -> Void

    var body: some View {
        Picker("Bewertung", selection: Binding(get: { rating ?? 0 }, set: { onChange($0 == 0 ? nil : $0) })) {
            Text("Keine").tag(0)
            ForEach((1...10).reversed(), id: \.self) { value in
                Text("★ \(value) / 10").tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}

/// Free text up to 2000 characters (series, season or movie comment).
struct CommentSheet: View {
    let title: String
    let onSave: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, text: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(.horizontal)
                .onChange(of: text) { _, new in if new.count > 2000 { text = String(new.prefix(2000)) } }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") { onSave(text); dismiss() }
                    }
                }
        }
    }
}
