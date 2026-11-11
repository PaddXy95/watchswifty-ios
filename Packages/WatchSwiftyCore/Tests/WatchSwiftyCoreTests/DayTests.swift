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

    @Test func displaysGermanDate() {
        #expect(Day.display("2026-11-07", calendar: berlin) == "07.11.2026")
        #expect(Day.display("kaputt", calendar: berlin) == "kaputt")
    }
}
