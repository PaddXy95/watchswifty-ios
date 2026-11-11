import SwiftUI

/// Placeholder rows in the shape of the real content while it loads (instead of a spinner).
struct SkeletonRows: View {
    var count = 6
    var poster = false

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                if poster { RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 44, height: 66) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Titel einer Serie")
                    Text("S1E1 · Name der Folge").font(.caption)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// A whole list that is still loading.
struct ListSkeleton: View {
    var rows = 8
    var poster = false

    var body: some View {
        List {
            Section {
                SkeletonRows(count: rows, poster: poster)
            } header: {
                Text("Abschnitt").redacted(reason: .placeholder)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Wird geladen")
    }
}

/// The library grid while it loads.
struct GridSkeleton: View {
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 100, height: 150)
                        Text("Titel").font(.caption)
                    }
                    .frame(width: 100)
                }
            }
            .padding()
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Wird geladen")
    }
}

/// The statistics page while it loads.
struct StatsSkeleton: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Folgen", value: "120")
                LabeledContent("Serien", value: "12")
                LabeledContent("Filme", value: "8")
                LabeledContent("Zeit", value: "48 Std. 20 Min.")
            } header: {
                Text("Zeitraum")
            }
            Section {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(height: 200)
            } header: {
                Text("Verlauf")
            }
            Section {
                SkeletonRows(count: 3, poster: true)
            } header: {
                Text("Meistgesehene Serien")
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Wird geladen")
    }
}
