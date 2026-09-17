import Foundation
import Combine
import Supabase

@MainActor
final class NotificationDestinationViewModel: ObservableObject {
    @Published private(set) var notification: EmployeeNotification?
    @Published private(set) var assignment: Assignment?
    @Published private(set) var bulletin: Bulletin?
    @Published private(set) var loading = true
    @Published private(set) var failure: String?

    func load(id: UUID, userID: UUID) async {
        loading = true
        failure = nil
        assignment = nil
        bulletin = nil
        defer { loading = false }
        do {
            let client = SupabaseService.client
            let item: EmployeeNotification = try await client.from("notificaciones_app").select()
                .eq("id", value: id).eq("perfil_id", value: userID).single().execute().value
            notification = item
            guard let destination = item.destino_id,
                  !["asignacion_eliminada", "asignacion_retirada", "comunicado_eliminado"].contains(item.tipo ?? "") else { return }
            if item.destino_tipo == "asignacion" {
                let rows: [Assignment] = try await client.from("asignaciones")
                    .select("*,hitos_itinerario(*),asignacion_equipo(perfiles(id,nombre_completo,rol))")
                    .eq("id", value: destination).execute().value
                assignment = rows.first
            } else if item.destino_tipo == "comunicado" {
                let rows: [Bulletin] = try await client.from("comunicados").select()
                    .eq("id", value: destination).execute().value
                bulletin = rows.first
            }
        } catch { failure = AuthNotice.failure(error).message }
    }
}
