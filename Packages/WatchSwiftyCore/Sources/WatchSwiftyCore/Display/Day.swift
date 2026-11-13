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

    /// „gesehen am 06.11.2026“ or „gesehen 02.03.2025 – 06.11.2026“ (Netflix rows to review, as in the web); nil when
    /// the server sends no days (before 0.5.0).
    public static func watchedRange(first: String?, last: String?, calendar: Calendar = .current) -> String? {
        guard let last, !last.isEmpty else { return nil }
        let first = (first?.isEmpty ?? true) ? last : first!
        return first == last
            ? "gesehen am \(display(last, calendar: calendar))"
            : "gesehen \(display(first, calendar: calendar)) – \(display(last, calendar: calendar))"
    }

    /// Whole days from `today` to `day` (negative for the past); nil if either is not a day.
    public static func days(from today: String, to day: String, calendar: Calendar = .current) -> Int? {
        guard let start = date(from: today, calendar: calendar), let end = date(from: day, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    /// Airs today or within the next two days („weniger als 3 Tage“).
    public static func isSoon(_ day: String?, today: String, calendar: Calendar = .current) -> Bool {
        guard let day, let distance = days(from: today, to: day, calendar: calendar) else { return false }
        return (0..<3).contains(distance)
    }

    /// „heute“, „morgen“, „übermorgen“, „in 5 Tagen“; nil for the past.
    public static func relative(_ day: String, today: String, calendar: Calendar = .current) -> String? {
        guard let distance = days(from: today, to: day, calendar: calendar), distance >= 0 else { return nil }
        switch distance {
        case 0: return "heute"
        case 1: return "morgen"
        case 2: return "übermorgen"
        default: return "in \(distance) Tagen"
        }
    }
}
