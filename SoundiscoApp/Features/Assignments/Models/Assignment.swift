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
    let asignacion_equipo: [AssignmentTeamLink]?
    var asignacion_supervisores: [SupervisorAsignacion]? = nil
    var viewingUserID: UUID? = nil

    var personalMilestones: [Milestone]? {
        guard let viewingUserID,
              asignacion_supervisores?.contains(where: { $0.usuario_id == viewingUserID }) != true else { return nil }
        guard !milestones.isEmpty else { return nil }
        return milestones.filter { ($0.hitos_colaboradores ?? []).contains { $0.usuario_id == viewingUserID } }
    }

    var isField: Bool { tipo_flujo?.lowercased().contains("campo") == true }
    var milestones: [Milestone] { hitos_itinerario.sorted { ($0.orden ?? 0) < ($1.orden ?? 0) } }
    var nextMilestone: Milestone? {
        if let personalMilestones {
            return personalMilestones.first { milestone in
                !(milestone.hitos_colaboradores ?? []).contains { $0.usuario_id == viewingUserID && $0.confirmado }
            } ?? personalMilestones.last
        }
        return milestones.first { !$0.isCompleted } ?? milestones.last
    }
    var responsibleNames: [String] {
        asignacion_equipo?.compactMap { $0.perfiles?.nombre }.nilIfEmpty ?? ["Equipo asignado"]
    }
    var deadline: Date? {
        if let personalMilestones { return personalMilestones.last.flatMap { AgendaDate.parse($0.fecha_programada) } }
        return AgendaDate.parse(fecha_limite)
            ?? milestones.reversed().compactMap { AgendaDate.parse($0.fecha_programada) }.first
    }
    var completed: Bool {
        if let personalMilestones {
            return !personalMilestones.isEmpty && personalMilestones.allSatisfy {
                ($0.hitos_colaboradores ?? []).contains { $0.usuario_id == viewingUserID && $0.confirmado }
            }
        }
        if let estado { return ["completada", "completado", "finalizada", "finalizado"].contains(estado.lowercased()) }
        return isField && !milestones.isEmpty && milestones.allSatisfy { $0.completado == true }
    }
    func overdue(at date: Date) -> Bool {
        !completed && ((personalMilestones == nil && estado == "vencida") || deadline.map { $0 < date } == true)
    }
    var inProgress: Bool {
        if let personalMilestones {
            return personalMilestones.contains { milestone in
                (milestone.hitos_colaboradores ?? []).contains {
                    $0.usuario_id == viewingUserID && $0.confirmado
                }
            }
        }
        return estado == "en_curso"
    }
    func status(at date: Date) -> String { completed ? "Completada" : overdue(at: date) ? "Vencida" : "Pendiente" }

    nonisolated init(_ assignment: Asignacion) {
        id = assignment.id
        titulo = assignment.titulo
        tipo_flujo = assignment.tipoFlujo.rawValue
        ubicacion = assignment.ubicacion
        nivel_prioridad = assignment.prioridad.rawValue
        instrucciones = assignment.instruccionesOpcionales
        fecha_limite = assignment.fechaLimite.map { ISO8601DateFormatter().string(from: $0) }
        estado = assignment.estado.rawValue
        hitos_itinerario = assignment.hitos.map(Milestone.init)
        asignacion_equipo = assignment.asignadoA.map(AssignmentTeamLink.init)
        asignacion_supervisores = assignment.supervisores
    }
}

struct Milestone: Decodable, Identifiable {
    let id: UUID
    let orden: Int?
    let descripcion: String?
    let hora_estimada: String?
    let fecha_programada: String?
    let completado: Bool?
    let estado_hito: String?
    let notas_incidencias: String?
    let hora_real_completado: String?
    var sla_abierto: Bool? = nil
    var hitos_colaboradores: [HitoColaborador]? = nil
    var scheduleValue: String? { fecha_programada ?? hora_estimada }
    var isCompleted: Bool { completado == true || estado_hito == "completado" }

    nonisolated init(_ milestone: Hito) {
        id = milestone.id
        orden = milestone.orden
        descripcion = milestone.titulo
        hora_estimada = milestone.horaEstimada
        fecha_programada = milestone.fechaProgramada.map { ISO8601DateFormatter().string(from: $0) }
        completado = milestone.estado == .completado
        estado_hito = milestone.estado.rawValue
        notas_incidencias = milestone.notasIncidencias
        hora_real_completado = nil
        hitos_colaboradores = milestone.colaboradores
    }
}

struct AssignmentTeamLink: Decodable {
    let perfiles: Empleado?

    nonisolated init(_ employee: Empleado) {
        perfiles = employee
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
