import Foundation

/// Poster URLs on TMDB's image CDN, sized like the web UI (`Poster.swift` on the server).
public enum TMDBImage {
    static let widths = [92, 154, 185, 342, 500, 780]

    public static func url(path: String, pointWidth: Int, scale: Int) -> URL {
        let pixels = pointWidth * scale
        let width = widths.first { $0 >= pixels } ?? widths.last!
        return URL(string: "https://image.tmdb.org/t/p/w\(width)\(path)")!
    }
}
