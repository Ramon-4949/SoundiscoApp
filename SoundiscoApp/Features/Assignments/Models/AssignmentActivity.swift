import Foundation

struct MilestoneCheckIn: Decodable, Identifiable {
    let id: UUID
    let hito_id: UUID
    let usuario_id: UUID
    let created_at: String
    let evaluacion: String
}

struct AssignmentNote: Decodable, Identifiable {
    let id: UUID
    let usuario_id: UUID
    let contenido: String
    let created_at: String
}
