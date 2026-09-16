import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var agenda = AssignmentsViewModel()
    @StateObject private var profile = ProfileViewModel()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                if let employee = profile.profile {
                    if employee.rol == "admin" {
                        AdminDashboardView(nombre: employee.nombre_completo ?? auth.displayName)
                    } else {
                        AssignmentListView(agenda: agenda)
                    }
                } else if let error = profile.error {
                    ContentUnavailableView {
                        Label("No se pudo cargar el perfil", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Reintentar") {
                            Task { if let id = auth.userID { await profile.load(userID: id) } }
                        }
                    }
                } else {
                    ProgressView("Cargando perfil…")
                }
            }
                .tabItem { Label("Inicio", systemImage: "house") }.tag(0)
            NavigationStack { BulletinsView() }
                .tabItem { Label("Mensajes", systemImage: "bubble.left") }.tag(1)
            NavigationStack { AgendaCalendarView(agenda: agenda) }
                .tabItem { Label("Calendario", systemImage: "calendar") }.tag(2)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }.tag(3)
        }
        .task(id: auth.userID) {
            if let id = auth.userID {
                await profile.load(userID: id)
                await agenda.load(userID: id)
            }
        }
    }

}
