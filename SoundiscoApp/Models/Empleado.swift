import Foundation

enum RolEmpleado: String, Codable, CaseIterable, Sendable {
    case tecnico
    case admin
}

struct Empleado: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var nombre: String
    var rol: RolEmpleado
    var avatar: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case nombre = "nombre_completo"
        case rol
        case avatar = "avatar_url"
    }
}
