import Foundation

@main
struct AssignmentFeedQueryTests {
    static func main() throws {
        let user = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santo_Domingo")!
        let date = ISO8601DateFormatter().date(from: "2035-01-02T01:00:00Z")!
        let home = AssignmentFeedQuery(userID: user, filter: .pending, search: "  montaje  ")
        let day = AssignmentFeedQuery(userID: user, filter: .overdue, day: date, calendar: calendar)
        precondition(home.search == "montaje" && home.dayStart == nil && home.dayEnd == nil)
        precondition(day.dayStart == ISO8601DateFormatter().date(from: "2035-01-01T04:00:00Z"))
        precondition(day.dayEnd == ISO8601DateFormatter().date(from: "2035-01-02T04:00:00Z"))
        let sameDay = AssignmentFeedQuery(userID: user, filter: .overdue, day: date.addingTimeInterval(-3600), calendar: calendar)
        precondition(day == sameDay)
        precondition(home != day)
        precondition(home != AssignmentFeedQuery(userID: UUID(), filter: .pending, search: "montaje"))
        let request = AssignmentFeedRequest(query: day, page: 2)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        precondition(json["p_offset"] as? Int == 20 && json["p_limit"] as? Int == 10)
        precondition(json["p_status"] as? String == "overdue")
        precondition(json["p_day_start"] as? String == "2035-01-01T04:00:00Z")
        precondition(AssignmentFeedRequest(query: home, page: -1).pOffset == 0)
        precondition(AssignmentFilter.allCases.map(\.serverValue) == ["all", "pending", "overdue", "completed"])
        precondition(AssignmentFilter.homeOptions == [.pending, .overdue, .completed])
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = AssignmentFeedQuery(userID: user, filter: .all,
            day: ISO8601DateFormatter().date(from: "2026-03-08T12:00:00Z")!, calendar: calendar)
        let autumn = AssignmentFeedQuery(userID: user, filter: .all,
            day: ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!, calendar: calendar)
        precondition(spring.dayEnd!.timeIntervalSince(spring.dayStart!) == 23 * 3600)
        precondition(autumn.dayEnd!.timeIntervalSince(autumn.dayStart!) == 25 * 3600)
        print("PASS: query identity, page size/offset, RPC encoding, local dates and DST boundaries")
    }
}
