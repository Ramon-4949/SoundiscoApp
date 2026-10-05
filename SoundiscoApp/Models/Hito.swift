import Foundation

enum EstadoHito: String, Codable, CaseIterable, Sendable {
    case completado
    case enCurso = "en_curso"
    case bloqueado
}

struct Hito: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let asignacionID: UUID
    var orden: Int
    var titulo: String
    var horaEstimada: String
    var fechaProgramada: Date?
    var estado: EstadoHito
    var notasIncidencias: String?
    var colaboradores: [HitoColaborador]? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case asignacionID = "asignacion_id"
        case orden
        case titulo = "descripcion"
        case horaEstimada = "hora_estimada"
        case fechaProgramada = "fecha_programada"
        case estado = "estado_hito"
        case notasIncidencias = "notas_incidencias"
        case colaboradores = "hitos_colaboradores"
    }

    func estaHabilitado(en itinerario: [Hito]) -> Bool {
        let ordenados = itinerario.sorted { $0.orden < $1.orden }
        guard let indice = ordenados.firstIndex(where: { $0.id == id }) else { return false }
        return indice == 0 || ordenados[indice - 1].estado == .completado
    }
}

struct HitoDraft: Codable, Hashable, Sendable {
    var colaboradoresIDs: [UUID] = []
    var id: UUID
    var orden: Int
    var titulo: String
    var horaEstimada: String
    var fechaProgramada: Date
    var estado: EstadoHito
    var notasIncidencias: String?

    init(
        id: UUID = UUID(),
        orden: Int,
        titulo: String,
        fechaProgramada: Date,
        estado: EstadoHito = .bloqueado,
        notasIncidencias: String? = nil,
        colaboradoresIDs: [UUID] = []
    ) {
        self.id = id
        self.orden = orden
        self.titulo = titulo
        self.fechaProgramada = fechaProgramada
        self.horaEstimada = Self.sqlTime(from: fechaProgramada)
        self.estado = estado
        self.notasIncidencias = notasIncidencias
        self.colaboradoresIDs = colaboradoresIDs
    }

    private static func sqlTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct HitoColaborador: Codable, Hashable, Identifiable, Sendable {
    var id: UUID { usuario_id }
    let hito_id: UUID
    let usuario_id: UUID
    let estado: String
    let confirmado_at: Date?
    let hora_programada: Date?
    let perfiles: Empleado?

    var confirmado: Bool { confirmado_at != nil }
    var etiqueta: String {
        guard let confirmado_at, let hora_programada else { return "Sin confirmar" }
        let seconds = abs(confirmado_at.timeIntervalSince(hora_programada))
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_DO")
        formatter.calendar = calendar
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        let duration = formatter.string(from: seconds) ?? "<1 min"
        switch estado {
        case "temprano": return seconds >= 60 ? "Temprano (-\(duration))" : "Temprano (<1 min)"
        case "tardio": return seconds >= 60 ? "Tardío (+\(duration))" : "Tardío (<1 min)"
        default: return "A tiempo"
        }
    }
}

struct SupervisorAsignacion: Codable, Hashable, Sendable {
    let usuario_id: UUID
}
