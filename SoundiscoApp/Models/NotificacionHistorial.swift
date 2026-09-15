import Foundation

enum TipoNotificacion: String, Codable, CaseIterable, Sendable {
    case asignacion
    case cambioEstado = "cambio_estado"
    case comunicado
    case sistema
}

struct NotificacionHistorial: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var tipo: TipoNotificacion
    var mensaje: String
    var fechaCreacion: Date

    var tiempoTranscurrido: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_DO")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: fechaCreacion, relativeTo: .now)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case tipo
        case mensaje
        case fechaCreacion = "fecha_creacion"
    }
}
