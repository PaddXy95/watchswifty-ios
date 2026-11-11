import SwiftUI

/// Placeholder in the shape of a series or movie page while it loads (instead of a spinner).
struct DetailSkeleton: View {
    var rows = 6

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 100, height: 150)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Titel der Serie").font(.title2.bold())
                            Text("2024 · Läuft")
                        }
                    }
                    Text("Eine kurze Beschreibung der Handlung, die hier gleich erscheint und ein paar Zeilen lang ist.")
                        .font(.callout)
                }
                .padding(.vertical, 4)
                LabeledContent("Bewertung", value: "8 / 10")
                Text("Kommentar")
            }
            Section("Staffel 1") {
                ForEach(0..<rows, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1. Name der Folge")
                        Text("01.01.2024").font(.caption)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Wird geladen")
    }
}
