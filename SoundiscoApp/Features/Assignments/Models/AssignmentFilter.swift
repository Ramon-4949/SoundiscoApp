nonisolated enum AssignmentFilter: String, CaseIterable, Hashable {
    case all = "Todas", pending = "Pendientes", overdue = "Vencidas", completed = "Completadas"

    static let homeOptions: [AssignmentFilter] = [.pending, .overdue, .completed]

    var serverValue: String {
        switch self {
        case .all: "all"
        case .pending: "pending"
        case .overdue: "overdue"
        case .completed: "completed"
        }
    }
}
