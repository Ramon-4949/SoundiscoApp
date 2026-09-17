import Foundation

struct EmployeeProfile: Decodable {
    let id: UUID
    let nombre_completo: String?
    let rol: String?
    let telefono: String?
    let cargo: String?
}
