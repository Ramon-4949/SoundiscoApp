import Foundation

enum RolEmpleado: String, Codable, CaseIterable, Sendable {
    case empleado
    // Compatibilidad mientras se ejecuta la migración de roles en Supabase.
    case tecnico
    case admin
}

struct Empleado: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var nombre: String?
    var rol: RolEmpleado?

    enum CodingKeys: String, CodingKey {
        case id
        case nombre = "nombre_completo"
        case rol
    }

    init(id: UUID, nombre: String? = nil, rol: RolEmpleado? = nil) {
        self.id = id
        self.nombre = nombre
        self.rol = rol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nombre = try container.decodeIfPresent(String.self, forKey: .nombre)
        // Los roles desconocidos no otorgan privilegios ni impiden leer el perfil.
        let valorRol = try container.decodeIfPresent(String.self, forKey: .rol)
        rol = valorRol.flatMap(RolEmpleado.init(rawValue:))
    }
}
