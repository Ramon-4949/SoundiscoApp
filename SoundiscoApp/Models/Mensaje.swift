import Foundation

struct Mensaje: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var asunto: String
    var cuerpoMensaje: String
    var fechaEnvio: Date
    var leidoPor: [UUID]

    enum CodingKeys: String, CodingKey {
        case id
        case asunto
        case cuerpoMensaje = "mensaje"
        case fechaEnvio = "fecha_publicacion"
        case leidoPor = "leido_por"
    }

    init(id: UUID, asunto: String, cuerpoMensaje: String, fechaEnvio: Date, leidoPor: [UUID] = []) {
        self.id = id
        self.asunto = asunto
        self.cuerpoMensaje = cuerpoMensaje
        self.fechaEnvio = fechaEnvio
        self.leidoPor = leidoPor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        asunto = try container.decode(String.self, forKey: .asunto)
        cuerpoMensaje = try container.decode(String.self, forKey: .cuerpoMensaje)
        fechaEnvio = try container.decode(Date.self, forKey: .fechaEnvio)
        leidoPor = try container.decodeIfPresent([UUID].self, forKey: .leidoPor) ?? []
    }
}

struct MensajeDraft: Sendable {
    var asunto: String
    var cuerpoMensaje: String
}
