import Foundation

enum AppDateFormatter {
    private static func apiTimestamp() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = apiTimestamp().date(from: value) { return date }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: value)
    }

    static func time(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func fullDate(_ date: DateOnly, timeZone: TimeZone = .current) -> String {
        date.date(in: timeZone).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
