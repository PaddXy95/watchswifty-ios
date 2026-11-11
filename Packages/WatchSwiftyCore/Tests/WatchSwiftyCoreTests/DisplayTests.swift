import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@Suite struct DisplayTests {
    @Test(arguments: [(60, 3, "w185"), (40, 2, "w92"), (400, 3, "w780"), (100, 2, "w342")])
    func tmdbImageWidth(points: Int, scale: Int, size: String) {
        let url = TMDBImage.url(path: "/abc.jpg", pointWidth: points, scale: scale)
        #expect(url.absoluteString == "https://image.tmdb.org/t/p/\(size)/abc.jpg")
    }

    @Test func serviceDisplayNames() {
        #expect(ServiceValue.primeVideo.displayName == "Prime Video")
        #expect(ServiceValue.appleTV.displayName == "Apple TV+")
        #expect(ServiceValue.cinema.displayName == "Kino")
        #expect(ServiceValue.purchased.displayName == "Gekauft")
        #expect(ServiceValue.other.displayName == "Sonstiges")
        #expect(ServiceValue(rawValue: "crunchyroll").displayName == "Anderer Dienst")
        #expect(ServiceValue.known.allSatisfy { $0.displayName != "Anderer Dienst" })
    }
}
