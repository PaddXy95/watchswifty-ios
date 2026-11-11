import SwiftUI
import WatchSwiftyCore

/// TMDB poster in 2:3, sized for the screen like the web UI; a neutral placeholder without poster.
struct PosterImage: View {
    let path: String?
    var width: CGFloat = 60
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let path {
                AsyncImage(url: TMDBImage.url(path: path, pointWidth: Int(width), scale: Int(displayScale.rounded(.up)))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
    }
}
