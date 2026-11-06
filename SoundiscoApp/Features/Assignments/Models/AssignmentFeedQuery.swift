import Foundation

nonisolated struct AssignmentFeedQuery: Hashable {
    let userID: UUID
    let filter: AssignmentFilter
    let search: String
    let dayStart: Date?
    let dayEnd: Date?
    let personalized: Bool

    init(userID: UUID, filter: AssignmentFilter, search: String = "", day: Date? = nil,
         personalized: Bool = true, calendar: Calendar = .current) {
        self.userID = userID
        self.filter = filter
        self.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        self.personalized = personalized
        let interval = day.flatMap { calendar.dateInterval(of: .day, for: $0) }
        dayStart = interval?.start
        dayEnd = interval?.end
    }
}

nonisolated struct AssignmentFeedObservation: Hashable {
    let query: AssignmentFeedQuery?
    let isActive: Bool
    let revision: Int
}

nonisolated struct AssignmentFeedRequest: Encodable {
    let pOffset: Int
    let pLimit = 10
    let pStatus: String
    let pSearch: String
    let pDayStart: String?
    let pDayEnd: String?

    init(query: AssignmentFeedQuery, page: Int) {
        pOffset = max(0, page) * pLimit
        pStatus = query.filter.serverValue
        pSearch = query.search
        let formatter = ISO8601DateFormatter()
        pDayStart = query.dayStart.map(formatter.string(from:))
        pDayEnd = query.dayEnd.map(formatter.string(from:))
    }

    enum CodingKeys: String, CodingKey {
        case pOffset = "p_offset", pLimit = "p_limit", pStatus = "p_status", pSearch = "p_search"
        case pDayStart = "p_day_start", pDayEnd = "p_day_end"
    }
}
