import Foundation

nonisolated enum AccountAccessState: String, Decodable, CaseIterable, Identifiable {
    case pendiente, aprobada, rechazada
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pendiente: "Pendientes"
        case .aprobada: "Aprobadas"
        case .rechazada: "Rechazadas"
        }
    }
}

nonisolated struct AccountAccess: Decodable {
    let estado: AccountAccessState
}

nonisolated struct ManagedAccount: Decodable, Identifiable {
    let id: UUID
    let nombre: String?
    let email: String?
    let telefono: String?
    let cargo: String?
    let estado: AccountAccessState
    let fecha: Date
    var displayName: String { nombre?.isEmpty == false ? nombre! : "Sin nombre" }
}
