import SwiftUI

struct NotificationDestinationView: View {
    let notificationID: UUID
    @EnvironmentObject private var auth: SessionViewModel
    @EnvironmentObject private var notifications: NotificationsViewModel
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var model = NotificationDestinationViewModel()

    var body: some View {
        Group {
            if model.loading { ProgressView("Cargando detalle…") }
            else if let assignment = model.assignment {
                AssignmentDetailView(assignment: assignment, allowsChecklistUpdates: !isAdministrator)
            } else if let bulletin = model.bulletin {
                BulletinDetailView(bulletin: bulletin)
            } else {
                ContentUnavailableView {
                    Label(model.notification?.titulo ?? "Notificación", systemImage: "bell")
                } description: {
                    Text(model.failure ?? model.notification?.mensaje ?? "Este aviso ya no está disponible para tu cuenta.")
                    if let destination = model.notification?.destino_tipo,
                       ["asignacion", "comunicado"].contains(destination), model.failure == nil {
                        Text("El contenido se eliminó o ya no está asignado a tu cuenta.")
                    }
                } actions: {
                    if model.failure != nil { Button("Reintentar") { Task { await load() } } }
                }
            }
        }.task(id: notificationID) { await load() }
    }
    private func load() async {
        guard let userID = auth.userID else { return }
        await model.load(id: notificationID, userID: userID)
        if model.notification != nil { await notifications.markRead(notificationID) }
    }
}
