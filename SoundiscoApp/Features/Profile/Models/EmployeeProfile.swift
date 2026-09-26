import Foundation

struct EmployeeProfile: Decodable, Identifiable {
    let id: UUID
    let nombre_completo: String?
    let rol: String?
    let telefono: String?
    let cargo: String?
    let nombre_usuario: String?
}
