import Foundation

enum TipoFlujo: String, Codable, CaseIterable, Sendable {
    case operacionesCampo = "campo"
    case tareaAdministrativa = "administrativa"
}

enum PrioridadAsignacion: String, Codable, CaseIterable, Sendable {
    case baja
    case media
    case alta
}

enum EstadoAsignacion: String, Codable, CaseIterable, Sendable {
    case pendiente
    case enCurso = "en_curso"
    case vencida
    case completada
}

struct Asignacion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var tipoFlujo: TipoFlujo
    var titulo: String
    var ubicacion: String?
    var prioridad: PrioridadAsignacion
    var instruccionesOpcionales: String?
    var estado: EstadoAsignacion
    var asignadoA: [Empleado]
    var fechaCreacion: Date
    var fechaLimite: Date?
    var hitos: [Hito]

    enum CodingKeys: String, CodingKey {
        case id
        case tipoFlujo = "tipo_flujo"
        case titulo
        case ubicacion
        case prioridad = "nivel_prioridad"
        case instruccionesOpcionales = "instrucciones"
        case estado
        case asignadoA = "asignado_a"
        case fechaCreacion = "fecha_creacion"
        case fechaLimite = "fecha_limite"
        case hitos = "hitos_itinerario"
        case equipo = "asignacion_equipo"
    }

    init(
        id: UUID,
        tipoFlujo: TipoFlujo,
        titulo: String,
        ubicacion: String?,
        prioridad: PrioridadAsignacion,
        instruccionesOpcionales: String?,
        estado: EstadoAsignacion,
        asignadoA: [Empleado],
        fechaCreacion: Date,
        fechaLimite: Date?,
        hitos: [Hito]
    ) {
        self.id = id
        self.tipoFlujo = tipoFlujo
        self.titulo = titulo
        self.ubicacion = ubicacion
        self.prioridad = prioridad
        self.instruccionesOpcionales = instruccionesOpcionales
        self.estado = estado
        self.asignadoA = asignadoA
        self.fechaCreacion = fechaCreacion
        self.fechaLimite = fechaLimite
        self.hitos = hitos.sorted { $0.orden < $1.orden }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tipoFlujo = try container.decode(TipoFlujo.self, forKey: .tipoFlujo)
        titulo = try container.decode(String.self, forKey: .titulo)
        ubicacion = try container.decodeIfPresent(String.self, forKey: .ubicacion)
        prioridad = try container.decode(PrioridadAsignacion.self, forKey: .prioridad)
        instruccionesOpcionales = try container.decodeIfPresent(String.self, forKey: .instruccionesOpcionales)
        estado = try container.decode(EstadoAsignacion.self, forKey: .estado)
        fechaCreacion = try container.decode(Date.self, forKey: .fechaCreacion)
        fechaLimite = try container.decodeIfPresent(Date.self, forKey: .fechaLimite)
        hitos = try container.decodeIfPresent([Hito].self, forKey: .hitos)?.sorted { $0.orden < $1.orden } ?? []

        if let empleados = try container.decodeIfPresent([Empleado].self, forKey: .asignadoA) {
            asignadoA = empleados
        } else {
            asignadoA = try container.decodeIfPresent([AsignacionEquipo].self, forKey: .equipo)?
                .compactMap(\.perfil) ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tipoFlujo, forKey: .tipoFlujo)
        try container.encode(titulo, forKey: .titulo)
        try container.encodeIfPresent(ubicacion, forKey: .ubicacion)
        try container.encode(prioridad, forKey: .prioridad)
        try container.encodeIfPresent(instruccionesOpcionales, forKey: .instruccionesOpcionales)
        try container.encode(estado, forKey: .estado)
        try container.encode(asignadoA, forKey: .asignadoA)
        try container.encode(fechaCreacion, forKey: .fechaCreacion)
        try container.encodeIfPresent(fechaLimite, forKey: .fechaLimite)
        try container.encode(hitos, forKey: .hitos)
    }

    func estadoEfectivo(at date: Date = .now) -> EstadoAsignacion {
        guard estado != .completada else { return .completada }
        if let fechaLimite, fechaLimite < date { return .vencida }
        return estado
    }
}

private struct AsignacionEquipo: Decodable {
    let perfil: Empleado?

    enum CodingKeys: String, CodingKey {
        case perfil = "perfiles"
    }
}

struct AsignacionDraft: Sendable {
    var id: UUID?
    var tipoFlujo: TipoFlujo
    var titulo: String
    var ubicacion: String?
    var prioridad: PrioridadAsignacion
    var instruccionesOpcionales: String?
    var estado: EstadoAsignacion
    var empleadosIDs: [UUID]
    var fechaCreacion: Date
    var fechaLimite: Date?
    var hitos: [HitoDraft]

    init(
        id: UUID? = nil,
        tipoFlujo: TipoFlujo,
        titulo: String,
        ubicacion: String? = nil,
        prioridad: PrioridadAsignacion,
        instruccionesOpcionales: String? = nil,
        estado: EstadoAsignacion = .pendiente,
        empleadosIDs: [UUID],
        fechaCreacion: Date = .now,
        fechaLimite: Date? = nil,
        hitos: [HitoDraft] = []
    ) {
        self.id = id
        self.tipoFlujo = tipoFlujo
        self.titulo = titulo
        self.ubicacion = ubicacion
        self.prioridad = prioridad
        self.instruccionesOpcionales = instruccionesOpcionales
        self.estado = estado
        self.empleadosIDs = empleadosIDs
        self.fechaCreacion = fechaCreacion
        self.fechaLimite = fechaLimite
        self.hitos = hitos
    }
}
