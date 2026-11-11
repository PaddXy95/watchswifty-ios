import Foundation

/// Calendar days as the API uses them (`yyyy-MM-dd`), in the device's calendar.
public enum Day {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let numbers = string.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3, string.count == 10 else { return nil }
        return calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2]))
    }

    /// `07.11.2026`, or the text unchanged if it is not a day.
    public static func display(_ string: String, calendar: Calendar = .current) -> String {
        guard let date = date(from: string, calendar: calendar) else { return string }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }
}
