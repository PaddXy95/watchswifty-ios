import SwiftUI

/// A comment written right in the page: grows with the text, saves when the field loses focus (or on „Fertig“).
struct CommentField: View {
    let placeholder: String
    let saved: String?
    let onSave: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private func saveIfChanged() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (saved ?? "") { onSave(trimmed) }
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...10)
            .focused($focused)
            .onAppear { text = saved ?? "" }
            .onChange(of: saved) { _, new in if !focused { text = new ?? "" } }
            .onChange(of: text) { _, new in if new.count > 2000 { text = String(new.prefix(2000)) } }
            .onChange(of: focused) { _, isFocused in if !isFocused { saveIfChanged() } }
            .onDisappear { saveIfChanged() }   // back swipe or tab switch while still typing
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fertig") { focused = false }
                    }
                }
            }
    }
}
