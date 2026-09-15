import Foundation

struct AssignmentLink: Decodable {
    let asignacion_id: UUID
    let asignaciones: Assignment?
}

struct Assignment: Decodable, Identifiable {
    let id: UUID
    let titulo: String
    let tipo_flujo: String?
    let ubicacion: String?
    let nivel_prioridad: String?
    let instrucciones: String?
    let fecha_limite: String?
    let estado: String?
    let hitos_itinerario: [Milestone]

    var isField: Bool { tipo_flujo?.lowercased().contains("campo") == true }
    var milestones: [Milestone] { hitos_itinerario.sorted { ($0.orden ?? 0) < ($1.orden ?? 0) } }
    var nextMilestone: Milestone? { milestones.first { $0.completado != true } ?? milestones.last }
    var deadline: Date? { AgendaDate.parse(fecha_limite) }
    var completed: Bool {
        if let estado { return ["completada", "completado", "finalizada", "finalizado"].contains(estado.lowercased()) }
        return isField && !milestones.isEmpty && milestones.allSatisfy { $0.completado == true }
    }
    func overdue(at date: Date) -> Bool { !completed && deadline.map { $0 < date } == true }
    func status(at date: Date) -> String { completed ? "Completada" : overdue(at: date) ? "Vencida" : "Pendiente" }
}

struct Milestone: Decodable, Identifiable {
    let id: UUID
    let orden: Int?
    let descripcion: String?
    let hora_estimada: String?
    let fecha_programada: String?
    let completado: Bool?
    let estado_hito: String?
    var scheduleValue: String? { fecha_programada ?? hora_estimada }
}
