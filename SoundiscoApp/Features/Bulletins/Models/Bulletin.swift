import Foundation

struct Bulletin: Decodable, Identifiable {
    let id: UUID
    let asunto: String
    let mensaje: String
    let fecha_publicacion: String?
}
