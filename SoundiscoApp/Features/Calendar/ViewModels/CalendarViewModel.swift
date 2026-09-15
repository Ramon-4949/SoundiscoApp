import Foundation
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var selected = Date()
    func entries(in assignments: [Assignment]) -> [Assignment] {
        assignments.filter { item in
                    item.deadline.map { Calendar.current.isDate($0, inSameDayAs: selected) } == true
                        || item.milestones.contains { milestone in
                            AgendaDate.parse(milestone.scheduleValue).map { Calendar.current.isDate($0, inSameDayAs: selected) } == true
                        }
                }
    }
}
