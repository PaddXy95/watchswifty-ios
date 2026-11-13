import Foundation
import Testing
@testable import WatchSwiftyCore

@Suite struct DayTests {
    let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    @Test func dayStringUsesLocalCalendar() {
        let lateEvening = Date(timeIntervalSince1970: 1_794_434_400)   // 2026-11-11 23:00 Berlin = 22:00 UTC
        #expect(Day.string(from: lateEvening, calendar: berlin) == "2026-11-11")
    }

    @Test func parsesDay() {
        let date = Day.date(from: "2026-11-07", calendar: berlin)!
        #expect(Day.string(from: date, calendar: berlin) == "2026-11-07")
        #expect(Day.date(from: "07.11.2026", calendar: berlin) == nil)
    }

    @Test func watchedRangeAsInTheWeb() {
        #expect(Day.watchedRange(first: "2026-11-06", last: "2026-11-06", calendar: berlin) == "gesehen am 06.11.2026")
        #expect(Day.watchedRange(first: "2025-03-02", last: "2026-11-06", calendar: berlin) == "gesehen 02.03.2025 – 06.11.2026")
        #expect(Day.watchedRange(first: nil, last: "2026-11-06", calendar: berlin) == "gesehen am 06.11.2026")
        #expect(Day.watchedRange(first: nil, last: nil, calendar: berlin) == nil)
    }

    @Test func displaysGermanDate() {
        #expect(Day.display("2026-11-07", calendar: berlin) == "07.11.2026")
        #expect(Day.display("kaputt", calendar: berlin) == "kaputt")
    }

    @Test(arguments: [("2026-11-11", 0), ("2026-11-12", 1), ("2026-11-13", 2), ("2026-11-14", 3), ("2026-11-10", -1), ("2026-12-01", 20)])
    func daysBetween(day: String, expected: Int) {
        #expect(Day.days(from: "2026-11-11", to: day, calendar: berlin) == expected)
    }

    @Test func soonMeansWithinThreeDays() {
        #expect(Day.isSoon("2026-11-11", today: "2026-11-11", calendar: berlin))
        #expect(Day.isSoon("2026-11-13", today: "2026-11-11", calendar: berlin))
        #expect(!Day.isSoon("2026-11-14", today: "2026-11-11", calendar: berlin))
        #expect(!Day.isSoon("2026-11-10", today: "2026-11-11", calendar: berlin))
        #expect(!Day.isSoon(nil, today: "2026-11-11", calendar: berlin))
    }

    @Test func relativeLabels() {
        #expect(Day.relative("2026-11-11", today: "2026-11-11", calendar: berlin) == "heute")
        #expect(Day.relative("2026-11-12", today: "2026-11-11", calendar: berlin) == "morgen")
        #expect(Day.relative("2026-11-13", today: "2026-11-11", calendar: berlin) == "übermorgen")
        #expect(Day.relative("2026-11-16", today: "2026-11-11", calendar: berlin) == "in 5 Tagen")
        #expect(Day.relative("2026-11-10", today: "2026-11-11", calendar: berlin) == nil)
    }
}
