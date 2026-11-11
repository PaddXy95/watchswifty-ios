import Foundation

/// A time of day as the API sends it (`HH:MM`, e.g. the daily notification run in the server's time zone).
public struct ClockTime: Equatable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses `HH:MM` (also `H:MM`).
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2, (1...2).contains(parts[0].count),
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// `HH:MM`, as the API expects it.
    public var text: String {
        (hour < 10 ? "0" : "") + "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
    }

    /// For a picker that shows hours and minutes: this time on `day` in `calendar`'s time zone.
    public func date(on day: Date = .now, in calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Hour and minute of `date` in `calendar`'s time zone.
    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.hour = parts.hour ?? 0
        self.minute = parts.minute ?? 0
    }

    /// Gregorian calendar in UTC: picker and conversion agree on hour and minute without daylight-saving gaps.
    public static let pickerCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
