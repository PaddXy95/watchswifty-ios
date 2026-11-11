import SwiftUI
import WatchSwiftyCore

/// The poster full screen: shows the cached small poster at once, then the large one; pinch to zoom, tap to close.
struct PosterViewer: View {
    let path: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: TMDBImage.url(path: path, pointWidth: 500, scale: 3)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                AsyncImage(url: TMDBImage.url(path: path, pointWidth: 100, scale: 3)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .scaleEffect(zoom)
            .gesture(MagnifyGesture()
                .onChanged { zoom = max(1, $0.magnification) }
                .onEnded { _ in withAnimation(.snappy) { zoom = 1 } })
            .accessibilityLabel("Poster von \(title)")
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Schließen")
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }
}
