import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = NotificationsViewModel()
    var body: some View {
        List {
            if model.loading { ProgressView("Cargando notificaciones…") }
            else if let failure = model.failure {
                Text(failure)
                Button("Reintentar") { Task { if let id = auth.userID { await model.load(userID: id) } } }
            } else if model.items.isEmpty {
                ContentUnavailableView("Sin notificaciones", systemImage: "bell")
            } else {
                ForEach(model.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(item.titulo ?? "Notificación", systemImage: item.leida == true ? "bell" : "bell.badge")
                            .font(.headline)
                        Text(item.mensaje ?? "")
                        if let date = AgendaDate.parse(item.fecha_creacion) {
                            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("Notificaciones").task { if let id = auth.userID { await model.load(userID: id) } }.refreshable { if let id = auth.userID { await model.load(userID: id) } }
    }
}
