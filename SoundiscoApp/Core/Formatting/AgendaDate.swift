import Foundation

enum AgendaDate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func label(_ value: String?) -> String {
        guard let value else { return "Sin horario" }
        if let date = parse(value) { return date.formatted(date: .abbreviated, time: .shortened) }
        // A SQL time has no event date: display it without inventing a calendar day.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        if let date = formatter.date(from: value) {
            formatter.locale = Locale(identifier: "es_DO")
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        return value
    }
}
