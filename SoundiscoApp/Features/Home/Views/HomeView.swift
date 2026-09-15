import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var agenda = AssignmentsViewModel()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { AssignmentListView(agenda: agenda) }
                .tabItem { Label("Inicio", systemImage: "house") }.tag(0)
            NavigationStack { BulletinsView() }
                .tabItem { Label("Mensajes", systemImage: "bubble.left") }.tag(1)
            NavigationStack { AgendaCalendarView(agenda: agenda) }
                .tabItem { Label("Calendario", systemImage: "calendar") }.tag(2)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }.tag(3)
        }
        .task(id: auth.userID) {
            if let id = auth.userID { await agenda.load(userID: id) }
        }
    }

}
