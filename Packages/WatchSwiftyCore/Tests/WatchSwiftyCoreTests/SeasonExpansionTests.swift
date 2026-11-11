import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@Suite struct SeasonExpansionTests {
    /// seasons: (number, watched episodes, aired episodes, unaired episodes)
    func detail(_ seasons: [(Int, Int, Int, Int)]) throws -> Components.Schemas.SeriesDetail {
        let seasonJSON = seasons.map { number, watched, aired, unaired in
            let episodes = (0..<(aired + unaired)).map { index in
                let watches = index < watched ? #"[{"id":"0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B","origin":"manual"}]"# : "[]"
                return #"{"season":\#(number),"number":\#(index + 1),"name":"F","aired":\#(index < aired),"watches":\#(watches)}"#
            }
            return #"{"number":\#(number),"title":"Staffel \#(number)","watchedCount":\#(watched),"episodes":[\#(episodes.joined(separator: ","))]}"#
        }
        let json = #"{"tmdbId":1,"name":"X","links":{"tmdb":"t","imdb":"i","rottenTomatoes":"r"},"hidden":false,"followed":false,"seasons":[\#(seasonJSON.joined(separator: ","))]}"#
        return try JSONDecoder().decode(Components.Schemas.SeriesDetail.self, from: Data(json.utf8))
    }

    @Test func expandsFirstSeasonWithUnwatchedAiredEpisode() throws {
        let series = try detail([(1, 10, 10, 0), (2, 3, 8, 0), (3, 0, 8, 0)])
        #expect(SeriesStore.initiallyExpanded(series) == [2])
    }

    @Test func unairedEpisodesDoNotCount() throws {
        let series = try detail([(1, 10, 10, 0), (2, 4, 4, 6)])
        #expect(SeriesStore.initiallyExpanded(series) == [2])   // nothing left to watch: show the running season
    }

    @Test func newSeriesExpandsFirstSeason() throws {
        #expect(SeriesStore.initiallyExpanded(try detail([(1, 0, 8, 0), (2, 0, 8, 0)])) == [1])
    }

    @Test func completedSeriesStartsCollapsed() throws {
        #expect(SeriesStore.initiallyExpanded(try detail([(1, 8, 8, 0), (2, 8, 8, 0)])).isEmpty)
    }
}
