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
    var estado: EstadoHito
    var notasIncidencias: String?

    enum CodingKeys: String, CodingKey {
        case id
        case asignacionID = "asignacion_id"
        case orden
        case titulo = "descripcion"
        case horaEstimada = "hora_estimada"
        case estado = "estado_hito"
        case notasIncidencias = "notas_incidencias"
    }

    func estaHabilitado(en itinerario: [Hito]) -> Bool {
        let ordenados = itinerario.sorted { $0.orden < $1.orden }
        guard let indice = ordenados.firstIndex(where: { $0.id == id }) else { return false }
        return indice == 0 || ordenados[indice - 1].estado == .completado
    }
}

struct HitoDraft: Codable, Hashable, Sendable {
    var id: UUID
    var orden: Int
    var titulo: String
    var horaEstimada: String
    var estado: EstadoHito
    var notasIncidencias: String?

    init(
        id: UUID = UUID(),
        orden: Int,
        titulo: String,
        horaEstimada: String,
        estado: EstadoHito = .bloqueado,
        notasIncidencias: String? = nil
    ) {
        self.id = id
        self.orden = orden
        self.titulo = titulo
        self.horaEstimada = horaEstimada
        self.estado = estado
        self.notasIncidencias = notasIncidencias
    }
}
