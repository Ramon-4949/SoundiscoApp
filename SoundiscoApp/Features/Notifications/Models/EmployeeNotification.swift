import Foundation

struct EmployeeNotification: Decodable, Identifiable {
    let id: UUID
    let titulo: String?
    let mensaje: String?
    var leida: Bool?
    let fecha_creacion: String?
    let tipo: String?
    let destino_id: UUID?
    let destino_tipo: String?
    let estado: String?

    var unread: Bool { leida != true }
    var date: Date { AgendaDate.parse(fecha_creacion) ?? .distantPast }
    var symbol: String {
        if destino_tipo == "comunicado" { return "megaphone.fill" }
        if tipo == "asignacion_eliminada" { return "trash" }
        if tipo == "hito_completado" { return "checklist" }
        if estado == "completada" { return "checkmark.circle.fill" }
        if tipo == "recordatorio" { return "alarm" }
        return "tray.full.fill"
    }
}
