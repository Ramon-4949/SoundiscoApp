import Foundation

struct AdminDashboardMetrics: Equatable, Sendable {
    var unidadesAsignadas: Int
    var unidadesActivas: Int
    var tasaEntrega: Double

    static let empty = AdminDashboardMetrics(
        unidadesAsignadas: 0,
        unidadesActivas: 0,
        tasaEntrega: 0
    )
}

enum FiltroAsignacionAdmin: String, CaseIterable, Sendable {
    case todas
    case pendientes
    case vencidas
    case completadas
}

enum AdminDataError: LocalizedError, Sendable {
    case tituloRequerido
    case responsableRequerido
    case ubicacionRequerida
    case itinerarioRequerido
    case tareaAdministrativaConItinerario
    case secuenciaHitosInvalida
    case hitosFueraPeriodo
    case mensajeInvalido
    case respuestaInvalida

    var errorDescription: String? {
        switch self {
        case .tituloRequerido:
            return "La asignación necesita un título."
        case .responsableRequerido:
            return "Selecciona al menos un empleado responsable."
        case .ubicacionRequerida:
            return "Una operación de campo necesita ubicación."
        case .itinerarioRequerido:
            return "La asignación necesita al menos un hito."
        case .tareaAdministrativaConItinerario:
            return "Una tarea administrativa no puede incluir ubicación."
        case .secuenciaHitosInvalida:
            return "Los hitos deben tener un orden único y no pueden avanzar si el anterior no está completado."
        case .hitosFueraPeriodo:
            return "Los hitos administrativos no pueden programarse antes de crear la asignación."
        case .mensajeInvalido:
            return "El comunicado necesita asunto y contenido."
        case .respuestaInvalida:
            return "Supabase devolvió una respuesta inesperada."
        }
    }
}
