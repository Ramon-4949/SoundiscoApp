enum AssignmentFilter: String, CaseIterable {
    case all = "Todas", pending = "Pendientes", overdue = "Vencidas", completed = "Completadas"

    static let homeOptions: [AssignmentFilter] = [.pending, .overdue, .completed]
}
