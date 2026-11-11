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
