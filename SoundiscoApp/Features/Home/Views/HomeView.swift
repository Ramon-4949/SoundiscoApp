import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var agenda = AssignmentsViewModel()
    @StateObject private var profile = ProfileViewModel()
    @StateObject private var notifications = NotificationsViewModel()
    @ObservedObject private var push = PushNotificationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var assignmentRefreshRevision = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                if let employee = profile.profile {
                    if employee.rol == "admin" {
                        AdminDashboardView(nombre: employee.nombre_completo ?? auth.displayName,
                            isActive: tab == 0, refreshRevision: assignmentRefreshRevision)
                    } else {
                        AssignmentListView(agenda: agenda, isActive: tab == 0, refreshRevision: assignmentRefreshRevision)
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
                .badge(notifications.unreadMessageCount)
            NavigationStack { AgendaCalendarView(isActive: tab == 2, refreshRevision: assignmentRefreshRevision) }
                .tabItem { Label("Calendario", systemImage: "calendar") }.tag(2)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }.tag(3)
        }
        .environment(\.isAdministrator, profile.profile?.rol == "admin")
        .environmentObject(notifications)
        .environmentObject(push)
        .task(id: auth.userID) {
            if let id = auth.userID { await notifications.observe(userID: id) }
        }
        .task(id: auth.userID) {
            if let id = auth.userID { await push.connect(userID: id) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let id = auth.userID {
                assignmentRefreshRevision += 1
                Task {
                    await push.connect(userID: id)
                    await notifications.load(userID: id)
                }
            }
        }
        .onChange(of: notifications.items.map(\.id)) { oldIDs, newIDs in
            guard oldIDs != newIDs else { return }
            assignmentRefreshRevision += 1
        }
        .onChange(of: push.receivedNotificationID) { _, _ in
            guard let id = auth.userID else { return }
            Task { await notifications.load(userID: id) }
        }
        .sheet(item: $push.route) { route in
            NavigationStack {
                if route.recipient == auth.userID {
                    NotificationDestinationView(notificationID: route.id)
                } else {
                    ContentUnavailableView("Aviso de otra cuenta", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
            .environmentObject(notifications)
            .environment(\.isAdministrator, profile.profile?.rol == "admin")
        }
        .task(id: auth.userID) {
            if let id = auth.userID {
                await profile.load(userID: id)
            }
        }
    }

}
