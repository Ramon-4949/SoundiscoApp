import Foundation

struct EmployeeNotification: Decodable, Identifiable {
    let id: UUID
    let titulo: String?
    let mensaje: String?
    let leida: Bool?
    let fecha_creacion: String?
}
